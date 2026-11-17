import Foundation

public enum WallpaperKind: String, Codable, Sendable {
    case video, still
}

public enum WallpaperOrigin: String, Codable, Sendable {
    /// Added by the user from their own files.
    case imported
    /// Downloaded from the online catalogue.
    case catalogue
}

/// One wallpaper in the user's library: a looping video or a still image.
public struct Wallpaper: Identifiable, Codable, Hashable, Sendable {
    public static let categories = ["Nature", "Space", "Abstract", "City", "Ocean", "Minimal", "Dark", "Others"]

    /// The built-in categories plus any others in use (a catalogue entry or
    /// a library wallpaper may name a new one): built-ins first in their
    /// usual order, then new ones alphabetically, and "Others" always last.
    public static func categories(including used: [String]) -> [String] {
        var seen = Set(categories.map { $0.lowercased() })
        var extras: [String] = []
        for name in used {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            extras.append(trimmed)
        }
        extras.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return categories.filter { $0 != "Others" } + extras + ["Others"]
    }

    public let id: UUID
    public var title: String
    /// File name inside `AppPaths.media`.
    public var fileName: String
    public var kind: WallpaperKind
    public var origin: WallpaperOrigin
    public var category: String
    public var width: Int
    public var height: Int
    public var duration: Double
    public var frameRate: Double
    public var hasAudio: Bool
    public var fileSize: Int64
    public var isFavorite: Bool
    public var dateAdded: Date
    public var lastPlayed: Date?
    public var playCount: Int
    /// For wallpapers downloaded from the catalogue: its id there, and the
    /// licence and credit it was published with.
    public var catalogueID: String?
    public var license: String?
    public var credit: String?
    public var sourceURL: URL?

    public init(
        id: UUID = UUID(),
        title: String,
        fileName: String,
        kind: WallpaperKind = .video,
        origin: WallpaperOrigin = .imported,
        category: String = "Others",
        width: Int,
        height: Int,
        duration: Double = 0,
        frameRate: Double = 0,
        hasAudio: Bool = false,
        fileSize: Int64 = 0,
        isFavorite: Bool = false,
        dateAdded: Date = Date(),
        lastPlayed: Date? = nil,
        playCount: Int = 0,
        catalogueID: String? = nil,
        license: String? = nil,
        credit: String? = nil,
        sourceURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.kind = kind
        self.origin = origin
        self.category = category
        self.width = width
        self.height = height
        self.duration = duration
        self.frameRate = frameRate
        self.hasAudio = hasAudio
        self.fileSize = fileSize
        self.isFavorite = isFavorite
        self.dateAdded = dateAdded
        self.lastPlayed = lastPlayed
        self.playCount = playCount
        self.catalogueID = catalogueID
        self.license = license
        self.credit = credit
        self.sourceURL = sourceURL
    }

    public var fileURL: URL { AppPaths.media.appendingPathComponent(fileName) }
    public var thumbnailURL: URL { AppPaths.thumbnails.appendingPathComponent("\(id.uuidString).jpg") }
    /// The image handed to macOS as the static wallpaper: the file itself
    /// for stills, an extracted first frame for videos.
    public var stillURL: URL {
        kind == .still ? fileURL : AppPaths.stills.appendingPathComponent("\(id.uuidString).jpg")
    }

    public var isOnDisk: Bool { FileManager.default.fileExists(atPath: fileURL.path) }
    public var is4K: Bool { min(width, height) >= 2160 }
    public var isUltrawide: Bool { height > 0 && Double(width) / Double(height) >= 2.2 }

    public var durationLabel: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public var sizeLabel: String { Format.bytes(fileSize) }

    /// e.g. "3840×2160 · 149.5 MB · 0:31"
    public var detailLabel: String {
        var parts = ["\(width)×\(height)", sizeLabel]
        if kind == .video { parts.append(durationLabel) }
        return parts.joined(separator: " · ")
    }
}

public enum LibrarySort: String, CaseIterable, Identifiable, Sendable {
    case mostPlayed, newest, name, largest

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .mostPlayed: return "Most Played"
        case .newest: return "Newest"
        case .name: return "Name"
        case .largest: return "Largest"
        }
    }

    public var symbol: String {
        switch self {
        case .mostPlayed: return "heart"
        case .newest: return "clock"
        case .name: return "textformat"
        case .largest: return "externaldrive"
        }
    }

    public func sorted(_ items: [Wallpaper]) -> [Wallpaper] {
        switch self {
        case .mostPlayed: return items.sorted { ($0.playCount, $0.dateAdded) > ($1.playCount, $1.dateAdded) }
        case .newest: return items.sorted { $0.dateAdded > $1.dateAdded }
        case .name: return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .largest: return items.sorted { $0.fileSize > $1.fileSize }
        }
    }
}
