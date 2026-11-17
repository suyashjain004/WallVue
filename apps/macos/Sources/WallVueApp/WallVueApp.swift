import AppKit
import Carbon.HIToolbox
import Observation
import SwiftUI
import WallVueCore

enum AppTab: Int, CaseIterable, Identifiable {
    case home, explore, stills, library, playlists

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .explore: return "Explore"
        case .stills: return "Stills"
        case .library: return "Library"
        case .playlists: return "Playlists"
        }
    }
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case general, wallpaper, lockScreen, sound, battery, displays, shortcuts, storage, help, about

    var id: String { rawValue }
}

/// App-wide state shared by the main window, the menu bar panel and Settings.
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let library: LibraryStore
    let engine: WallpaperEngine
    let catalogue: CatalogueStore
    let stats = ProcessStats()
    private let hotKeys = GlobalHotKeys()
    private var defaultsObserver: NSObjectProtocol?

    var tab: AppTab = .home
    /// The wallpaper whose full-window detail view is open, if any.
    var detailID: UUID?
    /// The catalogue wallpaper whose page is open, if any.
    var catalogueDetailID: String?
    /// Catalogue wallpapers being downloaded or added right now.
    private(set) var getting = Set<String>()
    var isUploadShown = false
    var isSearchShown = false
    var isImporterPresented = false
    var settingsPane: SettingsPane = .general
    /// Newest first; drives the "check the details" list on the upload page.
    var recentlyImported: [UUID] = []
    /// The video the loop maker sheet is open for, if any.
    var loopSource: Wallpaper?

    /// True while WallVue is hidden but still playing the wallpaper, which
    /// is what Quit does when "keep playing" is on.
    private(set) var isInBackground = false
    /// Set by Quit Completely, so the next quit really ends the app.
    @ObservationIgnored var isQuittingCompletely = false
    @ObservationIgnored private var parkedWindows: [NSWindow] = []

    enum UpdateState: Equatable {
        case idle, checking, upToDate, failed
        case available(AvailableUpdate)
    }
    private(set) var updateState: UpdateState = .idle

    private init() {
        SettingsDefaults.register()
        library = LibraryStore()
        engine = WallpaperEngine(library: library)
        let override = UserDefaults.standard.string(forKey: SettingsKey.catalogueURL).flatMap { URL(string: $0) }
        catalogue = CatalogueStore(
            remote: override ?? AppInfo.catalogueURL,
            bundled: Bundle.main.resourceURL?.appendingPathComponent("catalogue", isDirectory: true)
        )
        updateHotKeys()
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateHotKeys() }
        }
    }

    // MARK: Shortcuts that work in every app

    private func updateHotKeys() {
        let wanted = UserDefaults.standard.bool(forKey: SettingsKey.globalShortcuts)
        guard wanted != hotKeys.isRegistered else { return }
        guard wanted else {
            hotKeys.unregisterAll()
            return
        }
        let modifiers = controlKey | optionKey | cmdKey
        hotKeys.register([
            // ⌃⌥⌘P — play or pause
            .init(keyCode: kVK_ANSI_P, modifiers: modifiers) { [weak self] in
                guard let engine = self?.engine else { return }
                if engine.isActive { engine.togglePause() } else { engine.step(by: 1) }
            },
            // ⌃⌥⌘M — sound on or off
            .init(keyCode: kVK_ANSI_M, modifiers: modifiers) {
                let defaults = UserDefaults.standard
                defaults.set(!defaults.bool(forKey: SettingsKey.muted), forKey: SettingsKey.muted)
            },
        ])
    }

    // MARK: Catalogue

    /// Catalogue wallpapers that aren't in the library yet.
    var notDownloaded: [CatalogueEntry] {
        let have = Set(library.wallpapers.compactMap(\.catalogueID))
        return catalogue.entries.filter { !have.contains($0.id) }
    }

    func isGetting(_ entry: CatalogueEntry) -> Bool { getting.contains(entry.id) }

    func thumbnailURL(for item: BrowseItem) -> URL? {
        switch item {
        case .local(let wallpaper): return wallpaper.thumbnailURL
        case .remote(let entry): return catalogue.thumbnailFile(for: entry)
        }
    }

    func open(_ item: BrowseItem) {
        switch item {
        case .local(let wallpaper): open(wallpaper)
        case .remote(let entry): open(entry)
        }
    }

    func open(_ entry: CatalogueEntry) {
        if let wallpaper = library.wallpaper(catalogueID: entry.id) {
            open(wallpaper)
            return
        }
        isSearchShown = false
        isUploadShown = false
        detailID = nil
        catalogueDetailID = entry.id
    }

    /// Downloads a catalogue wallpaper into the library, and optionally
    /// puts it on the desktop when it arrives.
    func get(_ entry: CatalogueEntry, andSet: Bool) {
        if let existing = library.wallpaper(catalogueID: entry.id) {
            if andSet { engine.setWallpaper(existing) }
            return
        }
        guard getting.insert(entry.id).inserted else { return }
        Task {
            defer { getting.remove(entry.id) }
            do {
                try makeRoom(for: entry)
                let file = try await catalogue.download(entry)
                let wallpaper = try await library.addDownloaded(entry, file: file, thumbnail: catalogue.thumbnailFile(for: entry))
                if andSet { engine.setWallpaper(wallpaper) }
                if catalogueDetailID == entry.id {
                    catalogueDetailID = nil
                    detailID = wallpaper.id
                }
            } catch {
                library.lastError = "Couldn't download “\(entry.title)”. \(error.localizedDescription)"
            }
        }
    }

    /// Keeps downloads under the limit in Settings → Storage by removing
    /// the downloaded wallpapers played longest ago.
    private func makeRoom(for entry: CatalogueEntry) throws {
        let limit = Int64(max(1, UserDefaults.standard.integer(forKey: SettingsKey.downloadLimitGB))) * 1_000_000_000
        let showing = Set(library.wallpapers.filter { engine.isShowing($0) }.map(\.id))
        guard let leaving = Catalogue.evictions(
            toFit: entry.size, limit: limit, downloaded: library.downloaded, keeping: showing
        ) else { throw CatalogueError.noRoom(needed: entry.size, limit: limit) }
        for wallpaper in leaving { remove(wallpaper) }
    }

    /// What the corner toast should say, if anything is in progress.
    var activityText: String? {
        if library.importsInProgress > 0 { return "Adding \(library.importsInProgress)…" }
        guard let id = getting.sorted().first, let entry = catalogue.entry(id: id) else { return nil }
        let fraction = catalogue.progress[id] ?? 1
        let more = getting.count > 1 ? " and \(getting.count - 1) more" : ""
        return fraction < 1 ? "Downloading \(entry.title)\(more) · \(Int(fraction * 100))%" : "Adding \(entry.title)\(more)…"
    }

    // MARK: Playing in the background

    /// Hides every window and the Dock icon and leaves the wallpaper
    /// running. The menu bar item, or opening WallVue again, brings it back.
    func enterBackground() {
        detailID = nil
        catalogueDetailID = nil
        isSearchShown = false
        loopSource = nil
        parkedWindows = NSApp.windows.filter { $0.isVisible && $0.level == .normal && $0.canBecomeMain }
        for window in parkedWindows { window.orderOut(nil) }
        NSApp.setActivationPolicy(.accessory)
        isInBackground = true
    }

    /// Brings the Dock icon back, and the main window too unless the caller
    /// is about to show a window of its own.
    func leaveBackground(showMainWindow: Bool = true) {
        guard isInBackground else { return }
        isInBackground = false
        NSApp.setActivationPolicy(.regular)
        let main = parkedWindows.first { $0.identifier?.rawValue.hasPrefix("main") == true } ?? parkedWindows.first
        parkedWindows = []
        if showMainWindow { main?.makeKeyAndOrderFront(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Ends the app even when "keep playing after you quit" is on.
    func quitCompletely() {
        isQuittingCompletely = true
        NSApp.terminate(nil)
    }

    // MARK: Updates

    static var currentVersion: AppVersion? {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(AppVersion.init)
    }

    /// Asks GitHub whether a newer version exists. The automatic check runs
    /// at most once a day and stays quiet about failures.
    func checkForUpdates(userInitiated: Bool) {
        guard updateState != .checking,
              let current = Self.currentVersion,
              let repository = AppInfo.repositoryURL
        else { return }
        let defaults = UserDefaults.standard
        if !userInitiated {
            guard defaults.bool(forKey: SettingsKey.checkForUpdates) else { return }
            let last = defaults.double(forKey: SettingsKey.lastUpdateCheck)
            guard Date().timeIntervalSince1970 - last > 24 * 3600 else { return }
        }
        let previous = updateState
        updateState = .checking
        Task {
            do {
                let update = try await UpdateChecker.check(current: current, repository: repository)
                defaults.set(Date().timeIntervalSince1970, forKey: SettingsKey.lastUpdateCheck)
                updateState = update.map(UpdateState.available) ?? .upToDate
            } catch {
                updateState = userInitiated ? .failed : previous
            }
        }
    }

    var availableUpdate: AvailableUpdate? {
        if case .available(let update) = updateState { return update }
        return nil
    }

    // MARK: Loops

    func makeLoop(of wallpaper: Wallpaper, plan: LoopPlan) {
        Task {
            if let loop = await library.addLoop(of: wallpaper, plan: plan) {
                recentlyImported.insert(loop.id, at: 0)
            }
        }
    }

    // MARK: Reset and uninstall

    /// Stops the wallpaper, puts the system wallpaper and screen saver back,
    /// and deletes the library, caches and settings. The app keeps running
    /// and starts fresh.
    func resetEverything() {
        detailID = nil
        catalogueDetailID = nil
        isUploadShown = false
        recentlyImported = []
        engine.stop()
        library.removeAll()
        engine.resetSchedule()
        for folder in [AppPaths.thumbnails, AppPaths.stills, AppPaths.catalogueThumbnails, AppPaths.support.appendingPathComponent("LockScreen")] {
            let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
        ThumbnailCache.shared.clear()
        if let domain = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: domain)
        }
        SettingsDefaults.register()
        tab = .home
    }

    /// Reset, then remove the login item and the data folder, move the app
    /// to the Trash and quit.
    func uninstall() {
        resetEverything()
        try? LoginItem.set(false)
        try? FileManager.default.removeItem(at: AppPaths.support)
        NSWorkspace.shared.recycle([Bundle.main.bundleURL]) { _, _ in
            Task { @MainActor in AppModel.shared.quitCompletely() }
        }
    }

    func select(_ tab: AppTab) {
        self.tab = tab
        detailID = nil
        catalogueDetailID = nil
        isUploadShown = false
        isSearchShown = false
    }

    func open(_ wallpaper: Wallpaper) {
        isSearchShown = false
        isUploadShown = false
        catalogueDetailID = nil
        detailID = wallpaper.id
    }

    func showUpload() {
        detailID = nil
        catalogueDetailID = nil
        isSearchShown = false
        isUploadShown = true
    }

    func importFiles(_ urls: [URL]) {
        Task {
            let added = await library.importFiles(urls)
            recentlyImported = added.map(\.id) + recentlyImported
        }
    }

    func remove(_ wallpaper: Wallpaper) {
        if detailID == wallpaper.id { detailID = nil }
        recentlyImported.removeAll { $0 == wallpaper.id }
        library.remove(wallpaper)
        engine.libraryDidRemove(wallpaper)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedAtLogin = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // macOS marks the launch it does for a login item.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == AEEventID(kAEOpenApplication),
           let reason = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) {
            launchedAtLogin = reason.enumCodeValue == OSType(keyAELaunchedAsLogInItem)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let model = AppModel.shared
        model.engine.start()
        model.checkForUpdates(userInitiated: false)
        Task { await model.catalogue.refresh() }

        // Started by macOS at login: play the wallpaper without putting a
        // window in the user's way.
        if launchedAtLogin, model.engine.isActive,
           UserDefaults.standard.bool(forKey: SettingsKey.keepPlayingAfterQuit) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { model.enterBackground() }
        }
    }

    /// With "keep playing after you quit" on, Quit hides WallVue and leaves
    /// the wallpaper running. Logging out, restarting, shutting down and
    /// quits sent by scripts or installers always go through.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let model = AppModel.shared
        guard !model.isQuittingCompletely,
              UserDefaults.standard.bool(forKey: SettingsKey.keepPlayingAfterQuit),
              model.engine.isActive,
              Self.isOrdinaryQuit()
        else { return .terminateNow }
        model.enterBackground()
        return .terminateCancel
    }

    /// True for ⌘Q, the app menu's Quit and the Dock's Quit.
    private static func isOrdinaryQuit() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEQuitApplication)
        else { return true }   // the menu item and ⌘Q don't arrive as Apple events
        if event.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil { return false }
        guard let pid = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value,
              let sender = NSRunningApplication(processIdentifier: pid)
        else { return false }
        return sender.bundleIdentifier == "com.apple.dock"
    }

    /// Opening WallVue again (Finder, Spotlight, Launchpad) while it plays
    /// in the background brings its window back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        let model = AppModel.shared
        if model.isInBackground {
            model.leaveBackground()
        }
        let hasWindow = sender.windows.contains { $0.isVisible && $0.level == .normal && $0.canBecomeMain }
        if !hasWindow,
           let main = sender.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            main.makeKeyAndOrderFront(nil)
            return false
        }
        return !hasWindow
    }

    /// Files dropped on the Dock icon, or opened with "Open With → WallVue".
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        AppModel.shared.importFiles(files)
        AppModel.shared.showUpload()
    }

    // The wallpaper keeps playing with the window closed; the menu bar item
    // (or the Dock icon) is how you get back in.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct WallVueApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true

    var body: some Scene {
        Window(AppInfo.name, id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 940, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(model: model) }

        Window("\(AppInfo.name) Settings", id: "settings") {
            SettingsWindow()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarPanel()
                .environment(model)
                .preferredColorScheme(.dark)
        } label: {
            Image(systemName: "play.rectangle.on.rectangle.fill")
        }
        .menuBarExtraStyle(.window)
    }
}

struct AppCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "settings") }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
            Button("Quit Completely") { model.quitCompletely() }
                .keyboardShortcut("q", modifiers: [.option, .command])
        }
        CommandGroup(replacing: .newItem) {
            Button("Upload a Wallpaper…") { model.showUpload() }
                .keyboardShortcut("n")
            Button("Search") { model.isSearchShown = true }
                .keyboardShortcut("k")
        }
        CommandMenu("Wallpaper") {
            Button(model.engine.userPaused ? "Play" : "Pause") { model.engine.togglePause() }
                .keyboardShortcut("p", modifiers: [.option, .command])
                .disabled(!model.engine.isActive)
            Button("Next Wallpaper") { model.engine.step(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .command])
            Button("Previous Wallpaper") { model.engine.step(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .command])
            Button("Shuffle Now") { model.engine.shuffleNow() }
            Divider()
            Button("Refresh Catalogue") { Task { await model.catalogue.refresh(force: true) } }
                .keyboardShortcut("r")
            Button("Stop Wallpaper") { model.engine.stop() }
                .disabled(!model.engine.isActive)
        }
        CommandMenu("Go") {
            ForEach(AppTab.allCases) { tab in
                Button(tab.title) { model.select(tab) }
                    .keyboardShortcut(KeyEquivalent(Character("\(tab.rawValue + 1)")))
            }
        }
    }
}
