import Foundation
import ImageIO
import Observation

/// The user's collection of wallpapers. Files are copied into the app's own
/// folder on import, so the library keeps working if the original is moved.
@MainActor
@Observable
public final class LibraryStore {
    public private(set) var wallpapers: [Wallpaper] = []
    /// Number of files currently being imported (drives the progress UI).
    public private(set) var importsInProgress = 0
    /// Last user-facing import problem; the UI shows and clears it.
    public var lastError: String?

    private let fileURL: URL

    public static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
    public static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tiff", "tif"]
    /// MacWall's limit; keeps a careless drop of a whole folder manageable.
    public static let maxImportBatch = 10

    public init(fileURL: URL = AppPaths.libraryFile) {
        self.fileURL = fileURL
        AppPaths.ensureDirectories()
        load()
    }

    public var videos: [Wallpaper] { wallpapers.filter { $0.kind == .video } }
    public var stills: [Wallpaper] { wallpapers.filter { $0.kind == .still } }
    public var favorites: [Wallpaper] { wallpapers.filter(\.isFavorite) }

    public func wallpaper(id: UUID?) -> Wallpaper? {
        guard let id else { return nil }
        return wallpapers.first { $0.id == id }
    }

    /// Other wallpapers that resemble `wallpaper`: same category first.
    public func similar(to wallpaper: Wallpaper, limit: Int = 14) -> [Wallpaper] {
        let others = wallpapers.filter { $0.id != wallpaper.id && $0.kind == wallpaper.kind }
        let same = others.filter { $0.category == wallpaper.category }
        let rest = others.filter { $0.category != wallpaper.category }
        return Array((same + rest).prefix(limit))
    }

    // MARK: Importing

    /// Imports supported videos and images. Returns the new wallpapers;
    /// skipped or broken files are reported through `lastError`.
    @discardableResult
    public func importFiles(_ urls: [URL]) async -> [Wallpaper] {
        let supported = urls.filter {
            let ext = $0.pathExtension.lowercased()
            return Self.videoExtensions.contains(ext) || Self.imageExtensions.contains(ext)
        }
        if supported.isEmpty, !urls.isEmpty {
            lastError = "Only MP4, MOV and M4V videos, or JPEG, PNG and HEIC images, can be added."
            return []
        }
        let batch = Array(supported.prefix(Self.maxImportBatch))
        var failures: [String] = []
        if supported.count > batch.count {
            failures.append("Only the first \(Self.maxImportBatch) files were added. Add the rest in another batch.")
        }

        importsInProgress += batch.count
        var added: [Wallpaper] = []
        for url in batch {
            do {
                let wallpaper = try await importOne(url)
                wallpapers.insert(wallpaper, at: 0)
                added.append(wallpaper)
                save()
            } catch {
                failures.append(error.localizedDescription)
            }
            importsInProgress -= 1
        }
        if !failures.isEmpty { lastError = failures.joined(separator: "\n") }
        return added
    }

    private func importOne(_ source: URL) async throws -> Wallpaper {
        let ext = source.pathExtension.lowercased()
        let isVideo = Self.videoExtensions.contains(ext)
        let id = UUID()
        let fileName = "\(id.uuidString).\(ext)"
        let destination = AppPaths.media.appendingPathComponent(fileName)

        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }

        var wallpaper: Wallpaper
        if isVideo {
            let info = try await MediaTools.inspect(source)
            try FileManager.default.copyItem(at: source, to: destination)
            wallpaper = Wallpaper(
                id: id, title: Self.prettyTitle(from: source), fileName: fileName, kind: .video,
                width: info.width, height: info.height, duration: info.duration,
                frameRate: info.frameRate, hasAudio: info.hasAudio
            )
            // A missing thumbnail is cosmetic; never fail the import over it.
            let previewTime = min(1.0, info.duration / 2)
            if let image = try? await MediaTools.frame(of: destination, at: previewTime, maxDimension: 960) {
                try? MediaTools.writeJPEG(image, to: wallpaper.thumbnailURL, quality: 0.82)
            }
        } else {
            let size = try MediaTools.imageSize(of: source)
            try FileManager.default.copyItem(at: source, to: destination)
            wallpaper = Wallpaper(
                id: id, title: Self.prettyTitle(from: source), fileName: fileName, kind: .still,
                width: size.width, height: size.height
            )
            if let image = MediaTools.imageThumbnail(of: destination, maxDimension: 960) {
                try? MediaTools.writeJPEG(image, to: wallpaper.thumbnailURL, quality: 0.82)
            }
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path)
        wallpaper.fileSize = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return wallpaper
    }

    static func prettyTitle(from url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let collapsed = raw.split(separator: " ").joined(separator: " ")
        return collapsed.isEmpty ? "Untitled" : collapsed
    }

    // MARK: Editing

    public func toggleFavorite(_ wallpaper: Wallpaper) {
        update(wallpaper.id) { $0.isFavorite.toggle() }
    }

    public func rename(_ wallpaper: Wallpaper, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        update(wallpaper.id) { $0.title = trimmed }
    }

    public func setCategory(_ category: String, for wallpaper: Wallpaper) {
        update(wallpaper.id) { $0.category = category }
    }

    public func markPlayed(_ id: UUID) {
        update(id) {
            $0.playCount += 1
            $0.lastPlayed = Date()
        }
    }

    /// Removes the wallpaper and the files the app created for it.
    public func remove(_ wallpaper: Wallpaper) {
        wallpapers.removeAll { $0.id == wallpaper.id }
        var files = [wallpaper.fileURL, wallpaper.thumbnailURL]
        if wallpaper.kind == .video { files.append(wallpaper.stillURL) }
        for url in files { try? FileManager.default.removeItem(at: url) }
        save()
    }

    /// Removes every wallpaper and every file the app created for them.
    public func removeAll() {
        for wallpaper in wallpapers { remove(wallpaper) }
    }

    private func update(_ id: UUID, _ change: (inout Wallpaper) -> Void) {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { return }
        change(&wallpapers[index])
        save()
    }

    // MARK: Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        wallpapers = (try? decoder.decode([Wallpaper].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(wallpapers) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
