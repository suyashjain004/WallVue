import AppKit
import ServiceManagement
import SwiftUI
import WallVueCore

extension SettingsPane {
    var title: String {
        switch self {
        case .general: return "General"
        case .wallpaper: return "Wallpaper"
        case .lockScreen: return "Lock Screen"
        case .sound: return "Sound"
        case .battery: return "Battery & Performance"
        case .displays: return "Displays"
        case .shortcuts: return "Keyboard Shortcuts"
        case .storage: return "Storage"
        case .help: return "Help & Support"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape.fill"
        case .wallpaper: return "photo.fill"
        case .lockScreen: return "lock.fill"
        case .sound: return "speaker.wave.2.fill"
        case .battery: return "bolt.fill"
        case .displays: return "display"
        case .shortcuts: return "command"
        case .storage: return "internaldrive.fill"
        case .help: return "questionmark"
        case .about: return "info"
        }
    }

    var color: Color {
        switch self {
        case .general, .shortcuts, .about: return .gray
        case .wallpaper: return .cyan
        case .lockScreen: return .indigo
        case .sound: return .red
        case .battery: return .green
        case .displays: return .blue
        case .storage: return .orange
        case .help: return .teal
        }
    }

    var summary: String {
        switch self {
        case .general: return "Startup, the menu bar and your data."
        case .wallpaper: return "How wallpapers play, how they look and when they change."
        case .lockScreen: return "What the Lock Screen shows."
        case .sound: return "The wallpaper's sound."
        case .battery: return "Save battery and keep your Mac fast."
        case .displays: return "Every display connected to this Mac."
        case .shortcuts: return "Every shortcut WallVue has."
        case .storage: return "Wallpapers and caches on this Mac."
        case .help: return "Diagnostics and where your data lives."
        case .about: return "Version and licence."
        }
    }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

struct SettingsWindow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            List(selection: Binding<SettingsPane?>(
                get: { model.settingsPane },
                set: { if let pane = $0 { model.settingsPane = pane } }
            )) {
                ForEach(SettingsPane.allCases) { pane in
                    Label {
                        Text(pane.title)
                    } icon: {
                        PaneIcon(pane: pane, size: 22)
                    }
                    .tag(pane)
                }
            }
            .navigationSplitViewColumnWidth(230)
        } detail: {
            Form {
                Section {
                    HStack(spacing: 12) {
                        PaneIcon(pane: model.settingsPane, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.settingsPane.title).font(.headline)
                            Text(model.settingsPane.summary).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                pane(model.settingsPane)
            }
            .formStyle(.grouped)
            .navigationTitle(model.settingsPane.title)
        }
        .frame(width: 820, height: 600)
    }

    @ViewBuilder
    private func pane(_ pane: SettingsPane) -> some View {
        switch pane {
        case .general: GeneralPane()
        case .wallpaper: WallpaperPane()
        case .lockScreen: LockScreenPane()
        case .sound: SoundPane()
        case .battery: BatteryPane()
        case .displays: DisplaysPane()
        case .shortcuts: ShortcutsPane()
        case .storage: StoragePane()
        case .help: HelpPane()
        case .about: AboutPane()
        }
    }
}

private struct PaneIcon: View {
    let pane: SettingsPane
    let size: CGFloat

    var body: some View {
        Image(systemName: pane.symbol)
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(pane.color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
    }
}

// MARK: - Panes

private struct GeneralPane: View {
    @AppStorage(SettingsKey.showMenuBarIcon) private var showMenuBarIcon = true
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.restoreOnLaunch) private var restoreOnLaunch = true
    @AppStorage(SettingsKey.keepPlayingAfterQuit) private var keepPlayingAfterQuit = true
    @AppStorage(SettingsKey.checkForUpdates) private var checkForUpdates = true
    @State private var openAtLogin = false
    @State private var loginError: String?
    @State private var confirmsReset = false
    @State private var confirmsUninstall = false

    var body: some View {
        Section("Startup") {
            Toggle("Open at login", isOn: Binding(get: { openAtLogin }, set: setLogin))
            Toggle("Resume the last wallpaper when WallVue opens", isOn: $restoreOnLaunch)
            if let loginError {
                Text(loginError).font(.callout).foregroundStyle(.red)
            }
        }
        .onAppear { openAtLogin = LoginItem.isEnabled }

        Section {
            Toggle(isOn: $keepPlayingAfterQuit) {
                Text("Keep the wallpaper playing after you quit")
                Text("Quit hides WallVue and its Dock icon and leaves the wallpaper running.")
            }
        } header: {
            Text("Quitting")
        } footer: {
            Text("To stop the wallpaper as well, choose Quit Completely (⌥⌘Q) from the WallVue menu, or Quit in the menu bar panel. Opening WallVue again brings its window back.")
        }

        Section {
            Toggle(isOn: $checkForUpdates) {
                Text("Check for updates automatically")
                Text("Once a day, WallVue asks GitHub whether a newer version exists. Nothing about you is sent.")
            }
        } header: {
            Text("Updates")
        }

        Section {
            Toggle(isOn: $showMenuBarIcon) {
                Text("Show WallVue in the menu bar")
                Text("Click it for what's playing and quick controls.")
            }
        } header: {
            Text("Menu Bar")
        } footer: {
            Text("With the icon hidden, WallVue keeps playing; open it from the Dock, Spotlight or Applications.")
        }

        Section {
            LabeledContent("Library folder") {
                Button("Show in Finder") { NSWorkspace.shared.open(AppPaths.support) }
            }
            LabeledContent {
                Button("Reset…") { confirmsReset = true }
            } label: {
                Text("Reset WallVue")
                Text("Stops the wallpaper, restores your macOS wallpaper, and removes your library and settings.")
            }
            LabeledContent {
                Button("Uninstall…", role: .destructive) { confirmsUninstall = true }
            } label: {
                Text("Uninstall WallVue")
                Text("Does everything Reset does, then moves WallVue to the Trash.")
            }
        } header: {
            Text("Your Data")
        }
        .confirmationDialog("Reset WallVue?", isPresented: $confirmsReset) {
            Button("Reset", role: .destructive) { model.resetEverything() }
        } message: {
            Text("Your wallpapers, schedule and settings are deleted from this Mac. Your original video files are not touched. This can't be undone.")
        }
        .confirmationDialog("Uninstall WallVue?", isPresented: $confirmsUninstall) {
            Button("Uninstall", role: .destructive) { model.uninstall() }
        } message: {
            Text("WallVue restores your macOS wallpaper, deletes its library and settings, and moves itself to the Trash. This can't be undone.")
        }
    }

    private func setLogin(_ enabled: Bool) {
        do {
            try LoginItem.set(enabled)
            loginError = nil
        } catch {
            loginError = "Couldn't change the login item: \(error.localizedDescription)"
        }
        openAtLogin = LoginItem.isEnabled
    }
}

private struct WallpaperPane: View {
    @AppStorage(SettingsKey.scaling) private var scaling = ScalingMode.fill.rawValue
    @AppStorage(SettingsKey.playbackRate) private var playbackRate = 1.0
    @AppStorage(SettingsKey.dimAmount) private var dimAmount = 0.0
    @AppStorage(SettingsKey.blurAmount) private var blurAmount = 0.0
    @AppStorage(SettingsKey.shuffleEnabled) private var shuffleEnabled = false
    @AppStorage(SettingsKey.shuffleSource) private var shuffleSource = ShuffleSource.favorites.rawValue
    @AppStorage(SettingsKey.shuffleInterval) private var shuffleInterval = 3600.0
    @AppStorage(SettingsKey.scheduleEnabled) private var scheduleEnabled = false

    private static let intervals: [(String, Double)] = [
        ("15 minutes", 900), ("30 minutes", 1800), ("1 hour", 3600),
        ("3 hours", 10800), ("12 hours", 43200), ("Every day", 86400),
    ]

    var body: some View {
        Section {
            LabeledContent {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
            } label: {
                Text("WallVue App")
                Text("WallVue plays the desktop, and keeps playing after you quit if that is on in General. The Lock Screen and screen saver can play it too; see Lock Screen.")
            }
            LabeledContent {
                Text("Not available yet").foregroundStyle(.secondary)
            } label: {
                Text("System Wallpaper")
                Text("macOS itself would play the desktop, with no part of WallVue left running.")
            }
        } header: {
            Text("Playback")
        }

        Section {
            Picker("Screen fit", selection: $scaling) {
                ForEach(ScalingMode.allCases) { Text($0.label).tag($0.rawValue) }
            }
            Picker("Speed", selection: $playbackRate) {
                Text("0.5×").tag(0.5)
                Text("0.75×").tag(0.75)
                Text("Normal").tag(1.0)
                Text("1.5×").tag(1.5)
                Text("2×").tag(2.0)
            }
        } header: {
            Text("Appearance")
        } footer: {
            Text("Fill screen crops the edges; Fit to screen shows the whole wallpaper.")
        }

        Section {
            Slider(value: $dimAmount, in: 0...0.8) { Text("Dim") }
            Slider(value: $blurAmount, in: 0...1) { Text("Blur") }
        } header: {
            Text("Readability")
        } footer: {
            Text("Soften a busy wallpaper so desktop icons and widgets stay easy to read.")
        }

        Section {
            Toggle("Shuffle", isOn: $shuffleEnabled)
            Picker("Play From", selection: $shuffleSource) {
                ForEach(ShuffleSource.allCases) { Text($0.label).tag($0.rawValue) }
            }
            .disabled(!shuffleEnabled)
            Picker("Change Every", selection: $shuffleInterval) {
                ForEach(Self.intervals, id: \.1) { Text($0.0).tag($0.1) }
            }
            .disabled(!shuffleEnabled)
        } header: {
            Text("Shuffle")
        } footer: {
            Text("The same Shuffle as on the player bar. Turning it on turns the Day Schedule off. It waits while your Mac is locked or its displays sleep.")
        }
        .onChange(of: shuffleEnabled) { _, isOn in
            if isOn { scheduleEnabled = false }
        }
    }
}

private struct LockScreenPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.syncStillToSystem) private var syncStillToSystem = true
    @AppStorage(SettingsKey.liveLockScreen) private var liveLockScreen = false

    var body: some View {
        let bridge = model.engine.lockScreen

        Section {
            Toggle(isOn: $liveLockScreen) {
                Text("Play the wallpaper on the Lock Screen and screen saver")
                Text("macOS plays your video there itself, the way it plays Apple's Aerials, even when WallVue is closed.")
            }
            .disabled(!LockScreenBridge.isSupported)

            if !LockScreenBridge.isSupported {
                Text(LockScreenBridge.unsupportedReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if liveLockScreen {
                LabeledContent("Status") { statusView(bridge.status) }
            }
        } header: {
            Text("Live Lock Screen")
        } footer: {
            Text("Turning this on makes your video the macOS wallpaper and screen saver and restarts the macOS wallpaper service, so the desktop picture flickers once. Turning it off, or Stop Wallpaper, puts your previous wallpaper and screen saver back. The screen saver only starts if one is enabled in System Settings → Lock Screen.")
        }

        Section {
            Toggle(isOn: $syncStillToSystem) {
                Text("Otherwise, match the Lock Screen with a still")
                Text("Sets a still frame of the video as your macOS wallpaper, so the Lock Screen and Mission Control match the desktop.")
            }
            .disabled(liveLockScreen && LockScreenBridge.isSupported)
        } footer: {
            Text("Stop Wallpaper puts your previous picture back. If you were using an Aerial or dynamic wallpaper, reselect it in System Settings afterwards.")
        }

        Section("Now Showing") {
            if let current = model.engine.current {
                HStack(spacing: 12) {
                    ThumbnailImage(url: current.thumbnailURL)
                        .frame(width: 72, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading) {
                        Text(current.title)
                        Text(showingDescription(current, bridge.status))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("Your own macOS wallpaper").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func statusView(_ status: LockScreenBridge.Status) -> some View {
        switch status {
        case .off, .waiting:
            Text("Waiting for a video wallpaper").foregroundStyle(.secondary)
        case .preparing(let step):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(step)
            }
        case .active:
            Label("Playing on the Lock Screen", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Text(message).foregroundStyle(.red)
        }
    }

    private func showingDescription(_ current: Wallpaper, _ status: LockScreenBridge.Status) -> String {
        if current.kind == .still { return "The same still as the desktop" }
        if case .active(let id) = status, id == current.id { return "The same video as the desktop" }
        return syncStillToSystem ? "A still of the desktop wallpaper" : "Your own macOS wallpaper"
    }
}

private struct SoundPane: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.muted) private var muted = true
    @AppStorage(SettingsKey.volume) private var volume = 0.5

    var body: some View {
        Section {
            Toggle(isOn: Binding(get: { !muted }, set: { muted = !$0 })) {
                Text("Wallpaper sound")
                if let current = model.engine.current, !current.hasAudio {
                    Text("\(current.title) has no sound")
                }
            }
            Slider(value: $volume, in: 0...1) {
                Text("Volume")
            } minimumValueLabel: {
                Image(systemName: "speaker.fill")
            } maximumValueLabel: {
                Image(systemName: "speaker.wave.3.fill")
            }
            .disabled(muted)
        } footer: {
            Text("Only wallpapers with sound play audio. With several displays, sound comes from the main display only.")
        }
    }
}

private struct BatteryPane: View {
    @AppStorage(SettingsKey.pauseOnBattery) private var pauseOnBattery = false
    @AppStorage(SettingsKey.pauseInLowPowerMode) private var pauseInLowPowerMode = true
    @AppStorage(SettingsKey.pauseWhenCovered) private var pauseWhenCovered = true
    @AppStorage(SettingsKey.pauseWhenHot) private var pauseWhenHot = true
    @AppStorage(SettingsKey.pauseForCamera) private var pauseForCamera = true
    @AppStorage(SettingsKey.pauseForMicrophone) private var pauseForMicrophone = false
    @AppStorage(SettingsKey.pauseWhenScreenShared) private var pauseWhenScreenShared = false

    var body: some View {
        Section {
            Toggle(isOn: $pauseForCamera) {
                Text("Pause during video calls")
                Text("While any app is using your camera.")
            }
            Toggle(isOn: $pauseForMicrophone) {
                Text("Pause when the microphone is in use")
                Text("Covers voice calls. Dictation and recording apps count too.")
            }
            if CallMonitor.canDetectScreenCapture {
                Toggle(isOn: $pauseWhenScreenShared) {
                    Text("Pause while your screen is shared or recorded")
                    Text("Keeps a shared screen calm. Leave it off to record the wallpaper itself.")
                }
            }
        } header: {
            Text("Calls and Screen Sharing")
        } footer: {
            Text("WallVue only reads whether the camera, microphone or screen is in use. It never sees or hears anything, and asks for no permission.")
        }

        Section("Battery") {
            Toggle(isOn: $pauseOnBattery) {
                Text("Pause on battery")
                Text("Holds the frame while your Mac is unplugged and plays again when you plug it in.")
            }
            Toggle("Pause in Low Power Mode", isOn: $pauseInLowPowerMode)
        }

        Section {
            Toggle(isOn: $pauseWhenCovered) {
                Text("Pause when the desktop is covered")
                Text("Behind full-screen apps and when windows hide the whole desktop.")
            }
            Toggle(isOn: $pauseWhenHot) {
                Text("Pause when your Mac is running hot")
                Text("Gives games, exports and builds the full processor.")
            }
        } header: {
            Text("Performance")
        } footer: {
            Text("A paused wallpaper keeps its last frame and starts again on its own. Playback always stops while the display sleeps or the screen is locked.")
        }
    }
}

private struct DisplaysPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        Section {
            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(engine.isActive && engine.pauseReason == nil ? Color.green : Color.gray)
                        .frame(width: 7, height: 7)
                    Text(engine.statusLabel)
                }
            }
            LabeledContent("Displays", value: "\(engine.displays.count)")
        } footer: {
            Text(engine.displays.count > 1
                 ? "Right-click a wallpaper and choose Set on Display to give a display its own."
                 : "Connect another display to give it its own wallpaper.")
        }

        Section("Connected") {
            ForEach(engine.displays) { display in
                let wallpaper = engine.wallpaper(onDisplay: display.id)
                HStack(spacing: 12) {
                    ThumbnailImage(url: wallpaper?.thumbnailURL)
                        .frame(width: 84, height: 52)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(display.name)
                            if display.isMain {
                                Text("Main")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(.tint, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(display.detail).font(.callout).foregroundStyle(.secondary)
                        Text(wallpaper?.title ?? "Your own macOS wallpaper").font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct ShortcutsPane: View {
    @AppStorage(SettingsKey.globalShortcuts) private var globalShortcuts = true

    var body: some View {
        Section {
            Toggle(isOn: $globalShortcuts) {
                Text("Shortcuts that work in every app")
                Text("They work while you're in another app, with WallVue's window closed.")
            }
            row("Play or pause", "⌃⌥⌘P")
            row("Sound on or off", "⌃⌥⌘M")
        } header: {
            Text("In Every App")
        }

        Section {
            row("Play or pause", "⌥⌘P")
            row("Next wallpaper", "⌥⌘→")
            row("Previous wallpaper", "⌥⌘←")
            row("Search", "⌘K")
            row("Upload a wallpaper", "⌘N")
            row("Home, Explore and the other sections", "⌘1–⌘5")
            row("Settings", "⌘,")
        } header: {
            Text("While WallVue Is Open")
        }
    }

    private func row(_ title: String, _ keys: String) -> some View {
        LabeledContent(title) {
            Text(keys).monospaced().foregroundStyle(.secondary)
        }
    }
}

private struct StoragePane: View {
    @Environment(AppModel.self) private var model
    @State private var refresh = 0

    var body: some View {
        let media = AppPaths.size(of: AppPaths.media)
        let previews = AppPaths.size(of: AppPaths.thumbnails)
        let stills = AppPaths.size(of: AppPaths.stills)

        Section("On This Mac") {
            LabeledContent("Used by WallVue", value: Format.bytes(media + previews + stills))
            LabeledContent("Wallpapers", value: Format.bytes(media))
            LabeledContent {
                HStack {
                    Text(Format.bytes(stills)).foregroundStyle(.secondary)
                    Button("Clear…") {
                        clear(AppPaths.stills)
                    }
                }
            } label: {
                Text("Lock Screen stills")
                Text("First frames used as the macOS wallpaper; rebuilt when you set one.")
            }
        }
        .id(refresh)

        Section {
            ForEach(model.library.wallpapers) { wallpaper in
                HStack(spacing: 12) {
                    ThumbnailImage(url: wallpaper.thumbnailURL)
                        .frame(width: 56, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    VStack(alignment: .leading) {
                        Text(wallpaper.title)
                        Text("\(wallpaper.width)×\(wallpaper.height) · \(wallpaper.sizeLabel)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        model.remove(wallpaper)
                        refresh += 1
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red)
                    .help("Remove from Library")
                    .accessibilityLabel("Remove \(wallpaper.title)")
                }
            }
        } header: {
            Text("Wallpapers (\(model.library.wallpapers.count))")
        } footer: {
            Text("Removing a wallpaper deletes WallVue's copy from this Mac. Your original file is not touched.")
        }
    }

    private func clear(_ directory: URL) {
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for url in items { try? FileManager.default.removeItem(at: url) }
        refresh += 1
    }
}

private struct HelpPane: View {
    @Environment(\.openURL) private var openURL
    @State private var copied = false

    private var systemInfo: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion) · \(String(cString: model))"
    }

    var body: some View {
        if let repository = AppInfo.repositoryURL {
            Section("Get Help") {
                Button("Report a problem or ask a question") { openURL(repository.appendingPathComponent("issues")) }
            }
        }

        Section("Diagnostics") {
            LabeledContent("Version", value: "\(AppInfo.name) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
            LabeledContent {
                Button(copied ? "Copied" : "Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(systemInfo, forType: .string)
                    copied = true
                }
            } label: {
                Text("System information")
                Text(systemInfo)
            }
        }

        Section("Privacy") {
            Text("WallVue has no account, no analytics and no tracking. Your wallpapers and settings stay on this Mac. The only thing it fetches is the daily update check from GitHub, which you can turn off in General.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AboutPane: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Section {
            VStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 84, height: 84)
                Text(AppInfo.name).font(.title.weight(.bold))
                Text("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }

        Section("Updates") {
            LabeledContent {
                switch model.updateState {
                case .available(let update):
                    Button("Get Version \(update.version.description)") { NSWorkspace.shared.open(update.page) }
                case .checking:
                    ProgressView().controlSize(.small)
                default:
                    Button("Check Now") { model.checkForUpdates(userInitiated: true) }
                        .disabled(AppModel.currentVersion == nil)
                }
            } label: {
                switch model.updateState {
                case .available(let update):
                    Text("WallVue \(update.version.description) is available")
                    Text("Download it, then replace this copy in Applications.")
                case .upToDate:
                    Text("WallVue is up to date")
                case .failed:
                    Text("Couldn't check right now")
                    Text("GitHub didn't answer, or no version has been released yet.")
                case .idle, .checking:
                    Text("Check for a newer version")
                }
            }
        }

        Section("Licence") {
            Text("Free and open source under the MIT licence. No trial, no paid tier, no account.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
