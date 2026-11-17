import Foundation
import Observation

/// One downloadable wallpaper in the online list (`catalogue/index.json`).
public struct CatalogueEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public var title: String
    public var kind: WallpaperKind
    public var category: String
    public var width: Int
    public var height: Int
    public var duration: Double
    public var frameRate: Double
    /// Download size in bytes.
    public var size: Int64
    public var license: String
    public var credit: String
    /// Where the wallpaper comes from, for people who want to check.
    public var source: URL?
    public var thumbnail: URL?
    /// Download locations, tried in order.
    public var files: [URL]

    public var is4K: Bool { min(width, height) >= 2160 }
    public var isUltrawide: Bool { height > 0 && Double(width) / Double(height) >= 2.2 }

    /// e.g. "3840×2160 · 4.5 MB · 0:16"
    public var detailLabel: String {
        var parts = ["\(width)×\(height)", Format.bytes(size)]
        if kind == .video {
            let total = Int(duration.rounded())
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " · ")
    }
}

extension CatalogueEntry: Decodable {
    private enum Key: String, CodingKey {
        case id, title, kind, category, width, height, duration, frameRate, size, license, credit, source, thumbnail, files
    }

    /// An entry needs an id, a title, a licence, a credit and at least one
    /// download location. Everything else has a harmless default, so the
    /// list can gain fields without breaking older copies of the app.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Key.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        license = try c.decode(String.self, forKey: .license)
        credit = try c.decode(String.self, forKey: .credit)
        files = try c.decode([String].self, forKey: .files).compactMap { URL(string: $0) }
        guard !id.isEmpty, !files.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .files, in: c, debugDescription: "No usable download location")
        }
        kind = (try? c.decode(WallpaperKind.self, forKey: .kind)) ?? .video
        category = (try? c.decode(String.self, forKey: .category)) ?? "Others"
        width = (try? c.decode(Int.self, forKey: .width)) ?? 0
        height = (try? c.decode(Int.self, forKey: .height)) ?? 0
        duration = (try? c.decode(Double.self, forKey: .duration)) ?? 0
        frameRate = (try? c.decode(Double.self, forKey: .frameRate)) ?? 0
        size = (try? c.decode(Int64.self, forKey: .size)) ?? 0
        source = (try? c.decode(String.self, forKey: .source)).flatMap { URL(string: $0) }
        thumbnail = (try? c.decode(String.self, forKey: .thumbnail)).flatMap { URL(string: $0) }
    }
}

public enum CatalogueError: LocalizedError {
    case unavailable
    case noRoom(needed: Int64, limit: Int64)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "The download isn't available right now. Check your connection and try again."
        case .noRoom(let needed, let limit):
            return "It needs \(Format.bytes(needed)), and your download limit is \(Format.bytes(limit)). Raise the limit in Settings → Storage, or remove a downloaded wallpaper."
        }
    }
}

public enum Catalogue {
    private struct Lossy<Value: Decodable>: Decodable {
        let value: Value?
        init(from decoder: Decoder) { value = try? Value(from: decoder) }
    }

    private struct Index: Decodable {
        let wallpapers: [Lossy<CatalogueEntry>]
    }

    /// Reads the list. An entry that can't be understood is skipped rather
    /// than spoiling the rest; a repeated id keeps its first entry.
    public static func entries(inIndexJSON data: Data) throws -> [CatalogueEntry] {
        let index = try JSONDecoder().decode(Index.self, from: data)
        var seen = Set<String>()
        return index.wallpapers.compactMap(\.value).filter { seen.insert($0.id).inserted }
    }

    /// Which downloaded wallpapers to remove so that `incoming` more bytes
    /// fit under `limit`: the ones played longest ago go first; favourites
    /// and anything in `keeping` (what is on screen now) are never chosen.
    /// Returns nil when it can't be made to fit.
    public static func evictions(
        toFit incoming: Int64, limit: Int64, downloaded: [Wallpaper], keeping: Set<UUID>
    ) -> [Wallpaper]? {
        var used = downloaded.reduce(Int64(0)) { $0 + $1.fileSize }
        guard incoming <= limit else { return nil }
        if used + incoming <= limit { return [] }
        let candidates = downloaded
            .filter { !$0.isFavorite && !keeping.contains($0.id) }
            .sorted { ($0.lastPlayed ?? $0.dateAdded) < ($1.lastPlayed ?? $1.dateAdded) }
        var chosen: [Wallpaper] = []
        for wallpaper in candidates {
            chosen.append(wallpaper)
            used -= wallpaper.fileSize
            if used + incoming <= limit { return chosen }
        }
        return nil
    }
}

/// The list of downloadable wallpapers, and the downloading itself.
///
/// The list is read from three places, newest winning: the copy that ships
/// inside the app (so there is something to show on first launch and with
/// no connection), the copy saved from the last successful refresh, and the
/// live list online. Anything added to the online list therefore appears in
/// every installed copy of the app at its next refresh, with no app update.
@MainActor
@Observable
public final class CatalogueStore {
    public private(set) var entries: [CatalogueEntry] = []
    public private(set) var isRefreshing = false
    public private(set) var lastRefresh: Date?
    /// The last refresh could not reach or read the online list.
    public private(set) var refreshFailed = false
    /// Download progress, 0...1, for each entry being downloaded.
    public private(set) var progress: [String: Double] = [:]
    /// Bumped when a thumbnail arrives, so views showing it redraw.
    public private(set) var thumbnailRevision = 0

    /// How long a refreshed list is trusted before asking again.
    public static let refreshInterval: TimeInterval = 30 * 60

    private let remote: URL?
    private let bundled: URL?
    private let cacheFile: URL
    private let thumbnails: URL
    private let session: URLSession
    @ObservationIgnored private var thumbnailsInFlight = Set<String>()

    /// - Parameters:
    ///   - remote: the online `index.json`.
    ///   - bundled: a folder inside the app holding `index.json` and `thumbnails/`.
    public init(
        remote: URL?, bundled: URL?,
        cacheFile: URL = AppPaths.catalogueFile, thumbnails: URL = AppPaths.catalogueThumbnails,
        session: URLSession = .shared
    ) {
        self.remote = remote
        self.bundled = bundled
        self.cacheFile = cacheFile
        self.thumbnails = thumbnails
        self.session = session
        try? FileManager.default.createDirectory(at: thumbnails, withIntermediateDirectories: true)

        for source in [cacheFile, bundled?.appendingPathComponent("index.json")].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: source),
               let list = try? Catalogue.entries(inIndexJSON: data), !list.isEmpty {
                entries = list
                break
            }
        }
    }

    public func entry(id: String?) -> CatalogueEntry? {
        guard let id else { return nil }
        return entries.first { $0.id == id }
    }

    // MARK: The list

    /// Fetches the online list. Without `force`, does nothing if the list
    /// was refreshed recently. A failed refresh keeps the list already shown.
    public func refresh(force: Bool = false) async {
        guard let remote, !isRefreshing else { return }
        if !force, let lastRefresh, Date().timeIntervalSince(lastRefresh) < Self.refreshInterval { return }
        isRefreshing = true
        defer { isRefreshing = false }

        var request = URLRequest(url: remote, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,   // file URLs have no status
              let list = try? Catalogue.entries(inIndexJSON: data)
        else {
            refreshFailed = true
            return
        }
        refreshFailed = false
        lastRefresh = Date()
        thumbnailsInFlight.removeAll()   // give thumbnails that failed another try
        if list != entries { entries = list }
        try? data.write(to: cacheFile, options: .atomic)
    }

    // MARK: Thumbnails

    /// The thumbnail's file on this Mac, if it is here yet. When it isn't,
    /// it is fetched in the background and views redraw once it lands.
    public func thumbnailFile(for entry: CatalogueEntry) -> URL? {
        _ = thumbnailRevision
        let fm = FileManager.default
        let saved = thumbnails.appendingPathComponent("\(entry.id).jpg")
        if fm.fileExists(atPath: saved.path) { return saved }
        if let shipped = bundled?.appendingPathComponent("thumbnails/\(entry.id).jpg"), fm.fileExists(atPath: shipped.path) {
            return shipped
        }
        guard let url = entry.thumbnail, thumbnailsInFlight.insert(entry.id).inserted else { return nil }
        Task {
            if let (data, response) = try? await session.data(from: url),
               (response as? HTTPURLResponse).map({ $0.statusCode == 200 }) ?? true,
               (try? data.write(to: saved, options: .atomic)) != nil {
                thumbnailRevision += 1
            }
            // A failed fetch is retried the next time the list is refreshed.
        }
        return nil
    }

    // MARK: Downloading

    /// Downloads the entry's file to a temporary location and returns it;
    /// the caller moves it into the library. Each download location is
    /// tried in turn.
    public func download(_ entry: CatalogueEntry) async throws -> URL {
        progress[entry.id] = 0
        defer { progress[entry.id] = nil }
        var failure: Error = CatalogueError.unavailable
        for url in entry.files {
            do {
                return try await fetch(url, id: entry.id)
            } catch {
                failure = (error as? CatalogueError) ?? CatalogueError.unavailable
            }
        }
        throw failure
    }

    private func fetch(_ url: URL, id: String) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallvue-download-\(UUID().uuidString).\(url.pathExtension)")
        if url.isFileURL {
            try FileManager.default.copyItem(at: url, to: destination)
            progress[id] = 1
            return destination
        }

        var observation: NSKeyValueObservation?
        defer { observation?.invalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            let task = session.downloadTask(with: url) { temporary, response, error in
                guard error == nil, let temporary, (response as? HTTPURLResponse)?.statusCode == 200 else {
                    continuation.resume(throwing: CatalogueError.unavailable)
                    return
                }
                // The temporary file vanishes when this handler returns.
                do {
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    continuation.resume(returning: destination)
                } catch {
                    continuation.resume(throwing: CatalogueError.unavailable)
                }
            }
            observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
                let fraction = progress.fractionCompleted
                Task { @MainActor in
                    guard let self, self.progress[id] != nil else { return }
                    self.progress[id] = fraction
                }
            }
            task.resume()
        }
    }
}
