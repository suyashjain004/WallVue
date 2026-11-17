import Foundation

/// A dotted version number such as `1.4.2`. Missing parts count as zero,
/// so `1.4` equals `1.4.0`.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    /// Accepts `1.4.2` and `v1.4.2`. Anything else (for example the tag of
    /// a release that only holds wallpapers) is not a version.
    public init?(_ text: String) {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("v") || trimmed.hasPrefix("V") { trimmed.removeFirst() }
        let pieces = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(pieces.count) else { return nil }
        var numbers: [Int] = []
        for piece in pieces {
            guard !piece.isEmpty, piece.allSatisfy({ $0.isASCII && $0.isWholeNumber }), let number = Int(piece) else { return nil }
            numbers.append(number)
        }
        parts = numbers
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    private func part(_ index: Int) -> Int { index < parts.count ? parts[index] : 0 }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) where lhs.part(index) != rhs.part(index) {
            return lhs.part(index) < rhs.part(index)
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public func hash(into hasher: inout Hasher) {
        var trimmed = parts
        while trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }
}

public struct AvailableUpdate: Equatable, Sendable {
    public let version: AppVersion
    /// The release's page, where the download is.
    public let page: URL
}

public enum UpdateError: LocalizedError {
    case unreachable

    public var errorDescription: String? { "Couldn't check for updates right now." }
}

/// Asks GitHub which app release is newest. Nothing about the user or the
/// Mac is sent beyond what any web request carries.
public enum UpdateChecker {
    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft, prerelease
        }
    }

    /// The newest finished app release in GitHub's "list releases" reply.
    /// Drafts, pre-releases and releases whose tag isn't a version number
    /// (the ones that hold wallpaper files) are ignored.
    public static func newestRelease(inReleasesJSON data: Data) -> AvailableUpdate? {
        guard let releases = try? JSONDecoder().decode([Release].self, from: data) else { return nil }
        return releases
            .filter { !$0.draft && !$0.prerelease }
            .compactMap { release in
                AppVersion(release.tagName).map { AvailableUpdate(version: $0, page: release.htmlURL) }
            }
            .max { $0.version < $1.version }
    }

    /// GitHub's API address for a repository's releases, from its web address.
    public static func releasesAPI(forRepository repository: URL) -> URL? {
        let pieces = repository.path.split(separator: "/")
        guard repository.host == "github.com", pieces.count >= 2 else { return nil }
        return URL(string: "https://api.github.com/repos/\(pieces[0])/\(pieces[1])/releases?per_page=50")
    }

    /// Returns the newest release if it is newer than `current`, or nil when
    /// `current` is up to date.
    public static func check(
        current: AppVersion,
        repository: URL,
        session: URLSession = .shared
    ) async throws -> AvailableUpdate? {
        guard let url = releasesAPI(forRepository: repository) else { throw UpdateError.unreachable }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { throw UpdateError.unreachable }
        guard let newest = newestRelease(inReleasesJSON: data), newest.version > current else { return nil }
        return newest
    }
}
