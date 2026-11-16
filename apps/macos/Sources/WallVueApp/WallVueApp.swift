import AppKit
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
    let stats = ProcessStats()

    var tab: AppTab = .home
    /// The wallpaper whose full-window detail view is open, if any.
    var detailID: UUID?
    var isUploadShown = false
    var isSearchShown = false
    var isImporterPresented = false
    var settingsPane: SettingsPane = .general
    /// Newest first; drives the "check the details" list on the upload page.
    var recentlyImported: [UUID] = []

    private init() {
        SettingsDefaults.register()
        library = LibraryStore()
        engine = WallpaperEngine(library: library)
    }

    func select(_ tab: AppTab) {
        self.tab = tab
        detailID = nil
        isUploadShown = false
        isSearchShown = false
    }

    func open(_ wallpaper: Wallpaper) {
        isSearchShown = false
        isUploadShown = false
        detailID = wallpaper.id
    }

    func showUpload() {
        detailID = nil
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppModel.shared.engine.start()
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
