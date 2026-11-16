import Foundation

/// What is playing where. Persisted so the wallpaper comes back after a
/// relaunch or restart.
public struct EngineState: Codable, Equatable, Sendable {
    /// Wallpaper used on every display that has no specific assignment.
    public var defaultWallpaperID: UUID?
    /// Per-display overrides, keyed by the display's stable UUID string.
    public var assignments: [String: UUID] = [:]
    /// The image each display showed before we first replaced it with a
    /// still, so "Stop Wallpaper" can put it back. Display key → file path.
    public var originalDesktopImages: [String: String] = [:]

    public init() {}

    public var isActive: Bool { defaultWallpaperID != nil || !assignments.isEmpty }

    public func wallpaperID(forDisplay key: String) -> UUID? {
        assignments[key] ?? defaultWallpaperID
    }

    /// Drops references to wallpapers that no longer exist.
    public mutating func prune(keeping valid: Set<UUID>) {
        if let id = defaultWallpaperID, !valid.contains(id) { defaultWallpaperID = nil }
        assignments = assignments.filter { valid.contains($0.value) }
    }

    public static func load(from url: URL = AppPaths.stateFile) -> EngineState {
        guard let data = try? Data(contentsOf: url),
              let state = try? JSONDecoder().decode(EngineState.self, from: data)
        else { return EngineState() }
        return state
    }

    public func save(to url: URL = AppPaths.stateFile) {
        AppPaths.ensureDirectories()
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
