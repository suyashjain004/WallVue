import AppKit
import Observation
import WallVueCore

struct DisplayInfo: Identifiable, Equatable {
    let id: String   // NSScreen.displayKey
    let name: String
    let isMain: Bool
    let detail: String   // "3024 × 1964 · 120 Hz"
}

/// Owns the desktop windows: decides which wallpaper goes on which display,
/// keeps that in sync as displays come and go, pauses or resumes each one
/// according to `PlaybackPolicy`, and runs Shuffle and the Day Schedule.
@MainActor
@Observable
final class WallpaperEngine {
    private(set) var state = EngineState()
    private(set) var displays: [DisplayInfo] = []
    private(set) var userPaused = false
    /// Why the main display is not playing, if it isn't.
    private(set) var pauseReason: PauseReason?
    private(set) var schedule = DaySchedule()

    /// Plays the wallpaper on the Lock Screen and screen saver (macOS 26).
    let lockScreen = LockScreenBridge()

    private let library: LibraryStore
    private let power = PowerMonitor()
    @ObservationIgnored private var windows: [String: DesktopWindowController] = [:]
    @ObservationIgnored private var settings = SettingsSnapshot.load()
    @ObservationIgnored private var displayAsleep = false
    @ObservationIgnored private var sessionLocked = false
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private var shuffleTimer: Timer?
    @ObservationIgnored private var scheduleTimer: Timer?
    @ObservationIgnored private var lastScheduledWallpaper: UUID?

    init(library: LibraryStore) {
        self.library = library
    }

    // MARK: Read-only views of the state for the UI

    var isActive: Bool { state.isActive }

    /// The wallpaper on the main display.
    var current: Wallpaper? {
        let mainKey = displays.first(where: \.isMain)?.id ?? displays.first?.id
        guard let mainKey else { return library.wallpaper(id: state.defaultWallpaperID) }
        return library.wallpaper(id: state.wallpaperID(forDisplay: mainKey))
    }

    func wallpaper(onDisplay key: String) -> Wallpaper? {
        library.wallpaper(id: state.wallpaperID(forDisplay: key))
    }

    func isShowing(_ wallpaper: Wallpaper) -> Bool {
        if displays.isEmpty { return state.defaultWallpaperID == wallpaper.id }
        return displays.contains { state.wallpaperID(forDisplay: $0.id) == wallpaper.id }
    }

    /// Where the current wallpaper is showing, for the player bar.
    var targetLabel: String {
        guard let current else { return "Pick one from Home or Explore" }
        if current.kind == .still { return "Desktop & Lock Screen · Still" }
        if case .active(let id) = lockScreen.status, id == current.id { return "Desktop, Lock Screen & Screen Saver" }
        if case .preparing = lockScreen.status { return "Desktop · preparing the Lock Screen" }
        return settings.syncStillToSystem ? "Desktop · Lock Screen shows a still" : "Desktop"
    }

    var statusLabel: String {
        guard isActive, let current else { return "No wallpaper playing" }
        if current.kind == .still { return "Still image" }
        if let pauseReason { return pauseReason.label }
        return windows.count > 1 ? "Playing on \(windows.count) displays" : "Playing"
    }

    /// Most recently played wallpapers, newest first.
    var recents: [Wallpaper] {
        library.wallpapers
            .filter { $0.lastPlayed != nil }
            .sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) }
    }

    // MARK: Lifecycle

    func start() {
        guard !started else { return }
        started = true

        let valid = Set(library.wallpapers.map(\.id))
        state = EngineState.load()
        state.prune(keeping: valid)
        if !settings.restoreOnLaunch {
            state.defaultWallpaperID = nil
            state.assignments = [:]
        }
        schedule = DaySchedule.load()
        schedule.prune(keeping: valid)

        installObservers()
        power.onChange = { [weak self] in self?.applyPlayback() }
        power.start()
        reconcile()
        restartAutomation()
        updateLockScreen()
    }

    // MARK: Commands

    /// Sets `wallpaper` on one display, or on every display when `displayKey`
    /// is nil (which also clears per-display overrides).
    func setWallpaper(_ wallpaper: Wallpaper, onDisplay displayKey: String? = nil) {
        if let displayKey {
            state.assignments[displayKey] = wallpaper.id
        } else {
            state.defaultWallpaperID = wallpaper.id
            state.assignments = [:]
        }
        userPaused = false
        state.save()
        library.markPlayed(wallpaper.id)
        reconcile()
        syncSystemStills()
        updateLockScreen()
    }

    func togglePause() {
        guard isActive else { return }
        userPaused.toggle()
        applyPlayback()
    }

    /// Steps the all-displays wallpaper forwards or backwards through the
    /// library (same kind as what is playing; videos by default).
    func step(by offset: Int) {
        let kind = current?.kind ?? .video
        let pool = library.wallpapers.filter { $0.kind == kind }
        guard !pool.isEmpty else { return }
        let index = pool.firstIndex { $0.id == current?.id } ?? -1
        let next = ((index + offset) % pool.count + pool.count) % pool.count
        setWallpaper(pool[next])
    }

    /// Jumps to a random wallpaper from the Shuffle source.
    func shuffleNow() {
        var pool = settings.shuffleSource == .favorites ? library.favorites : library.wallpapers
        pool = pool.filter { $0.kind == .video }
        if pool.isEmpty { pool = library.videos }
        let candidates = pool.filter { $0.id != current?.id }
        guard let pick = (candidates.isEmpty ? pool : candidates).randomElement() else { return }
        setWallpaper(pick)
    }

    /// Stops playback everywhere and restores the wallpapers that were there
    /// before the app replaced them.
    func stop() {
        state.defaultWallpaperID = nil
        state.assignments = [:]
        userPaused = false
        lastScheduledWallpaper = nil
        reconcile()
        restoreEverything()
        state.save()
    }

    /// Call after a wallpaper is deleted from the library.
    func libraryDidRemove(_ wallpaper: Wallpaper) {
        let wasShowing = isShowing(wallpaper)
        let valid = Set(library.wallpapers.map(\.id))
        state.prune(keeping: valid)
        schedule.prune(keeping: valid)
        schedule.save()
        reconcile()
        if wasShowing, !state.isActive { restoreEverything() }
        state.save()
    }

    // MARK: Day Schedule

    func updateSlot(_ slot: ScheduleSlot) {
        schedule.upsert(slot)
        schedule.save()
        lastScheduledWallpaper = nil
        evaluateSchedule()
    }

    func removeSlot(_ id: UUID) {
        schedule.remove(id)
        schedule.save()
    }

    /// Back to the four empty default times.
    func resetSchedule() {
        schedule = DaySchedule()
        schedule.save()
        lastScheduledWallpaper = nil
    }

    private func evaluateSchedule() {
        guard settings.scheduleEnabled else { return }
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        guard let id = schedule.activeSlot(atMinutes: minutes)?.wallpaperID,
              id != lastScheduledWallpaper,
              let wallpaper = library.wallpaper(id: id)
        else { return }
        lastScheduledWallpaper = id
        if current?.id != id { setWallpaper(wallpaper) }
    }

    private func restartAutomation() {
        shuffleTimer?.invalidate()
        shuffleTimer = nil
        scheduleTimer?.invalidate()
        scheduleTimer = nil

        if settings.scheduleEnabled {
            lastScheduledWallpaper = nil
            evaluateSchedule()
            scheduleTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.evaluateSchedule() }
            }
        } else if settings.shuffleEnabled {
            shuffleTimer = Timer.scheduledTimer(withTimeInterval: settings.shuffleInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.shuffleTick() }
            }
        }
    }

    private func shuffleTick() {
        // Wait while nothing can be seen or the user asked for stillness.
        guard !displayAsleep, !sessionLocked, !userPaused, pauseReason != .battery else { return }
        shuffleNow()
    }

    // MARK: Window management

    private func reconcile() {
        let screens = NSScreen.screens
        let mainKey = screens.first?.displayKey
        displays = screens.map { screen in
            let size = screen.frame.size
            let scale = screen.backingScaleFactor
            let hz = screen.maximumFramesPerSecond
            return DisplayInfo(
                id: screen.displayKey,
                name: screen.localizedName,
                isMain: screen.displayKey == mainKey,
                detail: "\(Int(size.width * scale)) × \(Int(size.height * scale)) · \(hz) Hz"
            )
        }

        var live = Set<String>()
        for screen in screens {
            let key = screen.displayKey
            guard let wallpaper = library.wallpaper(id: state.wallpaperID(forDisplay: key)),
                  wallpaper.kind == .video, wallpaper.isOnDisk
            else { continue }
            live.insert(key)

            let controller: DesktopWindowController
            if let existing = windows[key] {
                controller = existing
            } else {
                controller = DesktopWindowController(screen: screen)
                controller.onVisibilityChange = { [weak self] in self?.applyPlayback() }
                windows[key] = controller
            }
            controller.update(screen: screen)
            controller.show(wallpaperID: wallpaper.id, url: wallpaper.fileURL)
        }

        for key in windows.keys where !live.contains(key) {
            windows.removeValue(forKey: key)?.close()
        }
        applyPlayback()
    }

    private func applyPlayback() {
        let mainKey = displays.first(where: \.isMain)?.id
        // Play sound from one display only, so identical clips don't echo.
        let audioKey = (mainKey.flatMap { windows[$0] != nil ? $0 : nil }) ?? windows.keys.sorted().first
        var mainReason: PauseReason?

        for (key, controller) in windows {
            var env = PlaybackEnvironment()
            env.userPaused = userPaused
            env.displayAsleep = displayAsleep
            env.sessionLocked = sessionLocked
            env.desktopVisible = controller.isDesktopVisible
            env.onBattery = power.onBattery
            env.lowPowerMode = power.lowPowerMode
            env.thermallyConstrained = power.thermallyConstrained

            let decision = PlaybackPolicy.decide(env, rules: settings.rules)
            let hasAudio = wallpaper(onDisplay: key)?.hasAudio ?? false
            controller.apply(
                playing: decision.isPlaying,
                rate: Float(settings.playbackRate),
                muted: settings.muted || key != audioKey || !hasAudio,
                volume: Float(settings.volume),
                scaling: settings.scaling,
                dim: settings.dimAmount,
                blur: settings.blurAmount
            )
            if key == audioKey, case .pause(let reason) = decision { mainReason = reason }
        }
        if pauseReason != mainReason { pauseReason = mainReason }
    }

    // MARK: System wallpaper
    //
    // While our window covers the desktop, the real system wallpaper is still
    // what macOS shows on the Lock Screen, in Mission Control and during
    // Space transitions. Setting it to the video's first frame keeps those
    // consistent with the live wallpaper. Still wallpapers are simply handed
    // to macOS.

    /// True when macOS itself is asked to play videos on the Lock Screen,
    /// which replaces the still-frame approach.
    private var usesLiveLockScreen: Bool { settings.liveLockScreen && LockScreenBridge.isSupported }

    private func updateLockScreen() {
        guard usesLiveLockScreen else { return }
        guard let wallpaper = current, wallpaper.kind == .video else {
            lockScreen.markWaiting()
            return
        }
        Task { await lockScreen.apply(wallpaper) }
    }

    /// Undoes every change made to the system wallpaper and screen saver.
    private func restoreEverything() {
        if lockScreen.isOn { lockScreen.restore() }
        restoreSystemWallpapers()
    }

    private func syncSystemStills() {
        for screen in NSScreen.screens {
            let key = screen.displayKey
            guard let wallpaper = wallpaper(onDisplay: key) else { continue }
            if wallpaper.kind == .video {
                guard settings.syncStillToSystem, !usesLiveLockScreen else { continue }
            }
            Task { await self.applyStill(of: wallpaper, toDisplay: key) }
        }
    }

    private func applyStill(of wallpaper: Wallpaper, toDisplay key: String) async {
        let still = wallpaper.stillURL
        if !FileManager.default.fileExists(atPath: still.path) {
            guard wallpaper.kind == .video,
                  let image = try? await MediaTools.frame(of: wallpaper.fileURL, at: 0, maxDimension: 0),
                  (try? MediaTools.writeJPEG(image, to: still, quality: 0.92)) != nil
            else { return }
        }
        // The selection may have changed while the frame was being extracted.
        guard state.wallpaperID(forDisplay: key) == wallpaper.id,
              let screen = NSScreen.screens.first(where: { $0.displayKey == key })
        else { return }

        let workspace = NSWorkspace.shared
        if state.originalDesktopImages[key] == nil,
           let existing = workspace.desktopImageURL(for: screen),
           !existing.path.hasPrefix(AppPaths.support.path) {
            state.originalDesktopImages[key] = existing.path
            state.save()
        }
        try? workspace.setDesktopImageURL(still, for: screen, options: [:])
    }

    private func restoreSystemWallpapers() {
        let workspace = NSWorkspace.shared
        for screen in NSScreen.screens {
            guard let path = state.originalDesktopImages[screen.displayKey],
                  FileManager.default.fileExists(atPath: path)
            else { continue }
            try? workspace.setDesktopImageURL(URL(fileURLWithPath: path), for: screen, options: [:])
        }
        state.originalDesktopImages = [:]
    }

    // MARK: System events

    private func installObservers() {
        let app = NotificationCenter.default
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()

        observe(app, NSApplication.didChangeScreenParametersNotification) { $0.reconcile() }
        observe(app, UserDefaults.didChangeNotification) { $0.settingsDidChange() }

        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.displayAsleep = true; $0.applyPlayback() }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displayAsleep = false; $0.applyPlayback() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.sessionLocked = true; $0.applyPlayback() }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.sessionLocked = false; $0.applyPlayback() }
        // Spaces can change what covers the desktop without an occlusion event.
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { $0.applyPlayback() }

        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.sessionLocked = true; $0.applyPlayback() }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.sessionLocked = false; $0.applyPlayback() }
    }

    private func observe(
        _ center: NotificationCenter,
        _ name: Notification.Name,
        _ handler: @escaping @MainActor (WallpaperEngine) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                handler(self)
            }
        }
        observers.append((center, token))
    }

    private func settingsDidChange() {
        let fresh = SettingsSnapshot.load()
        guard fresh != settings else { return }
        let old = settings
        settings = fresh
        applyPlayback()
        if fresh.liveLockScreen != old.liveLockScreen {
            if fresh.liveLockScreen {
                updateLockScreen()
            } else {
                if lockScreen.isOn { lockScreen.restore() }
                syncSystemStills()
            }
        } else if fresh.syncStillToSystem && !old.syncStillToSystem {
            syncSystemStills()
        }
        if fresh.shuffleEnabled != old.shuffleEnabled || fresh.shuffleInterval != old.shuffleInterval
            || fresh.scheduleEnabled != old.scheduleEnabled {
            restartAutomation()
        }
    }
}
