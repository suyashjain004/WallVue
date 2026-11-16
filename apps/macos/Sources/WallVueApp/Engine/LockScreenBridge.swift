import AVFoundation
import AppKit
import Observation
import WallVueCore

/// Makes macOS itself play a WallVue video on the Lock Screen and as the
/// screen saver, by registering it the way Apple's Aerials are registered.
///
/// This edits files macOS owns, so it is conservative: it only runs on the
/// macOS version it was verified against, it backs up what it changes before
/// the first change, and `restore()` puts everything back.
@MainActor
@Observable
final class LockScreenBridge {
    enum Status: Equatable {
        case off
        /// Turned on, but the current wallpaper is not a video.
        case waiting
        case preparing(String)
        case active(UUID)
        case failed(String)
    }

    struct Paths {
        var wallpaperBase: URL
        var backup: URL
        var converted: URL
        /// False in dry runs: no agent restart, no screen saver change.
        var touchesSystem = true

        static var live: Paths {
            let library = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            return Paths(
                wallpaperBase: library.appendingPathComponent("com.apple.wallpaper", isDirectory: true),
                backup: AppPaths.support.appendingPathComponent("SystemBackup", isDirectory: true),
                converted: AppPaths.support.appendingPathComponent("LockScreen", isDirectory: true)
            )
        }

        var videos: URL { wallpaperBase.appendingPathComponent("aerials/videos", isDirectory: true) }
        var thumbnails: URL { wallpaperBase.appendingPathComponent("aerials/thumbnails", isDirectory: true) }
        var entries: URL { wallpaperBase.appendingPathComponent("aerials/manifest/entries.json") }
        var store: URL { wallpaperBase.appendingPathComponent("Store/Index.plist") }
        var storeBackup: URL { backup.appendingPathComponent("Index.plist") }
        var screenSaverBackup: URL { backup.appendingPathComponent("screensaver.plist") }
    }

    private(set) var status: Status = .off
    @ObservationIgnored private let paths: Paths
    @ObservationIgnored private var generation = 0

    init(paths: Paths = .live) {
        self.paths = paths
        // A backup on disk means a previous run left the feature on.
        if FileManager.default.fileExists(atPath: paths.storeBackup.path),
           let id = Self.activeWallpaperID(paths: paths) {
            status = .active(id)
        }
    }

    /// The Aerials pipeline this relies on exists in macOS 26. Later versions
    /// changed it, so they stay off until verified.
    static var isSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
    }

    static var unsupportedReason: String {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        return major < 26
            ? "Video on the Lock Screen needs macOS 26. On this Mac the Lock Screen shows a still."
            : "This macOS version changed how Lock Screen video works. WallVue doesn't support it there yet."
    }

    var isOn: Bool { status != .off }

    /// The system wallpaper was replaced by something else (a still).
    func markWaiting() {
        generation += 1
        if status != .off { status = .waiting }
    }

    // MARK: Apply

    func apply(_ wallpaper: Wallpaper) async {
        guard Self.isSupported || !paths.touchesSystem else {
            status = .failed(Self.unsupportedReason)
            return
        }
        guard wallpaper.kind == .video else { return }
        if status == .active(wallpaper.id) { return }

        generation += 1
        let token = generation
        do {
            status = .preparing("Converting for the Lock Screen…")
            let converted = try await convertedVideo(for: wallpaper)
            guard token == generation else { return }

            status = .preparing("Handing it to macOS…")
            try install(wallpaper: wallpaper, video: converted)
            if paths.touchesSystem {
                setAerialsScreenSaver()
                restartWallpaperAgent()
            }
            status = .active(wallpaper.id)
        } catch {
            guard token == generation else { return }
            status = .failed(error.localizedDescription)
        }
    }

    /// Returns an HEVC QuickTime copy, converting once and caching it.
    private func convertedVideo(for wallpaper: Wallpaper) async throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.converted, withIntermediateDirectories: true)
        let output = paths.converted.appendingPathComponent("\(wallpaper.id.uuidString).mov")
        if fm.fileExists(atPath: output.path) { return output }

        let asset = AVURLAsset(url: wallpaper.fileURL)
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVCHighestQuality) else {
            throw BridgeError.conversionUnavailable
        }
        let temporary = paths.converted.appendingPathComponent("\(wallpaper.id.uuidString).partial.mov")
        try? fm.removeItem(at: temporary)
        if #available(macOS 15.0, *) {
            try await session.export(to: temporary, as: .mov)
        } else {
            session.outputURL = temporary
            session.outputFileType = .mov
            await session.export()
            if session.status != .completed { throw session.error ?? BridgeError.conversionFailed }
        }
        try fm.moveItem(at: temporary, to: output)
        return output
    }

    private func install(wallpaper: Wallpaper, video: URL) throws {
        let fm = FileManager.default
        let assetID = wallpaper.id.uuidString
        try backUpIfNeeded()

        try fm.createDirectory(at: paths.videos, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.thumbnails, withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.entries.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.store.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Remove videos from earlier wallpapers before adding this one.
        let existing = readEntries()
        for stale in AerialManifest.wallVueAssetIDs(in: existing) where stale != assetID {
            removeFiles(forAsset: stale)
        }

        let videoDestination = paths.videos.appendingPathComponent("\(assetID).mov")
        if !fm.fileExists(atPath: videoDestination.path) {
            try fm.copyItem(at: video, to: videoDestination)
        }
        let thumbnailDestination = paths.thumbnails.appendingPathComponent("\(assetID).png")
        if !fm.fileExists(atPath: thumbnailDestination.path),
           let image = NSImage(contentsOf: wallpaper.thumbnailURL),
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try png.write(to: thumbnailDestination, options: .atomic)
        }

        let entries = AerialManifest.settingAsset(
            id: assetID, name: wallpaper.title,
            videoURL: videoDestination, thumbnailURL: thumbnailDestination, in: existing
        )
        try JSONSerialization.data(withJSONObject: entries, options: [.prettyPrinted, .sortedKeys])
            .write(to: paths.entries, options: .atomic)

        let store = try WallpaperStore.settingAerial(assetID: assetID, in: readStore())
        try PropertyListSerialization.data(fromPropertyList: store, format: .binary, options: 0)
            .write(to: paths.store, options: .atomic)
    }

    // MARK: Restore

    /// Puts back the wallpaper and screen saver the user had before, and
    /// removes everything this bridge added.
    func restore() {
        generation += 1
        let fm = FileManager.default
        let entries = readEntries()
        for asset in AerialManifest.wallVueAssetIDs(in: entries) { removeFiles(forAsset: asset) }
        if fm.fileExists(atPath: paths.entries.path),
           let data = try? JSONSerialization.data(
               withJSONObject: AerialManifest.removingWallVue(from: entries), options: [.prettyPrinted, .sortedKeys]
           ) {
            try? data.write(to: paths.entries, options: .atomic)
        }

        let hadBackup = fm.fileExists(atPath: paths.storeBackup.path)
        if hadBackup, let original = try? Data(contentsOf: paths.storeBackup) {
            try? original.write(to: paths.store, options: .atomic)
        }
        if paths.touchesSystem, hadBackup {
            restoreScreenSaver()
            restartWallpaperAgent()
        }
        try? fm.removeItem(at: paths.backup)
        status = .off
    }

    // MARK: Backup

    private func backUpIfNeeded() throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: paths.storeBackup.path) else { return }
        try fm.createDirectory(at: paths.backup, withIntermediateDirectories: true)
        if fm.fileExists(atPath: paths.store.path) {
            try fm.copyItem(at: paths.store, to: paths.storeBackup)
        } else {
            // Nothing to restore to; an empty marker still records "we changed it".
            try Data().write(to: paths.storeBackup)
        }
        if paths.touchesSystem {
            run("/usr/bin/defaults", ["-currentHost", "export", "com.apple.screensaver", paths.screenSaverBackup.path])
        }
    }

    // MARK: Files

    private func readEntries() -> [String: Any] {
        guard let data = try? Data(contentsOf: paths.entries),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ["version": 1, "categories": [Any](), "assets": [Any]()] }
        return parsed
    }

    private func readStore() -> [String: Any] {
        guard let data = try? Data(contentsOf: paths.store),
              let parsed = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return parsed
    }

    private func removeFiles(forAsset id: String) {
        try? FileManager.default.removeItem(at: paths.videos.appendingPathComponent("\(id).mov"))
        try? FileManager.default.removeItem(at: paths.thumbnails.appendingPathComponent("\(id).png"))
    }

    private static func activeWallpaperID(paths: Paths) -> UUID? {
        guard let data = try? Data(contentsOf: paths.store),
              let store = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let asset = WallpaperStore.currentAerialAssetID(in: store)
        else { return nil }
        return UUID(uuidString: asset)
    }

    // MARK: System services

    private static let aerialsExtension = "/System/Library/ExtensionKit/Extensions/WallpaperAerialsExtension.appex"

    /// Points the screen saver at the Aerials extension, so it plays the same
    /// video as the Lock Screen.
    private func setAerialsScreenSaver() {
        run("/usr/bin/defaults", [
            "-currentHost", "write", "com.apple.screensaver", "moduleDict", "-dict",
            "moduleName", "WallpaperAerialsExtension", "path", Self.aerialsExtension, "type", "0",
        ])
    }

    private func restoreScreenSaver() {
        if FileManager.default.fileExists(atPath: paths.screenSaverBackup.path) {
            run("/usr/bin/defaults", ["-currentHost", "import", "com.apple.screensaver", paths.screenSaverBackup.path])
        }
    }

    /// macOS relaunches the agent by itself and reads the files again.
    private func restartWallpaperAgent() {
        run("/usr/bin/killall", ["WallpaperAgent"])
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

enum BridgeError: LocalizedError {
    case conversionUnavailable
    case conversionFailed

    var errorDescription: String? {
        switch self {
        case .conversionUnavailable: return "This video can't be converted for the Lock Screen on this Mac."
        case .conversionFailed: return "Converting the video for the Lock Screen failed."
        }
    }
}
