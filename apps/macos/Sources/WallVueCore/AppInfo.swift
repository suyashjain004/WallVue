import Foundation

/// Single place for the app's identity.
public enum AppInfo {
    public static let name = "WallVue"
    public static let bundleID = "io.github.wallvue"
    /// The project's home. Help links are hidden if this is nil.
    public static let repositoryURL: URL? = URL(string: "https://github.com/suyashjain004/WallVue")
    /// The live list of downloadable wallpapers.
    public static let catalogueURL: URL? = URL(string: "https://raw.githubusercontent.com/suyashjain004/WallVue/main/catalogue/index.json")
}

/// Where the app keeps its data: `~/Library/Application Support/WallVue/`.
public enum AppPaths {
    public static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Wallpaper files (videos and still images), named `<id>.<ext>`.
    public static var media: URL { support.appendingPathComponent("Media", isDirectory: true) }
    /// Small JPEG previews for grids.
    public static var thumbnails: URL { support.appendingPathComponent("Thumbnails", isDirectory: true) }
    /// Full-resolution first frames used as the system wallpaper still.
    public static var stills: URL { support.appendingPathComponent("Stills", isDirectory: true) }

    public static var libraryFile: URL { support.appendingPathComponent("library.json") }
    public static var stateFile: URL { support.appendingPathComponent("state.json") }
    public static var scheduleFile: URL { support.appendingPathComponent("schedule.json") }
    /// The catalogue list as last fetched, and thumbnails fetched for it.
    public static var catalogueFile: URL { support.appendingPathComponent("catalogue.json") }
    public static var catalogueThumbnails: URL { support.appendingPathComponent("CatalogueThumbnails", isDirectory: true) }

    public static func ensureDirectories() {
        for dir in [support, media, thumbnails, stills] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Total size in bytes of the regular files directly inside `directory`.
    public static func size(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys
        ) else { return 0 }
        return items.reduce(0) { total, url in
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { return total }
            return total + Int64(values?.fileSize ?? 0)
        }
    }
}

public enum Format {
    public static func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: count)
    }
}
