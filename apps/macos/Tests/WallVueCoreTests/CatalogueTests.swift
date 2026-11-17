import XCTest
@testable import WallVueCore

private func entryJSON(_ id: String, title: String? = nil, extra: String = "") -> String {
    """
    {"id": "\(id)", "title": "\(title ?? id.capitalized)", "kind": "video", "category": "Nature",
     "width": 3840, "height": 2160, "duration": 16, "frameRate": 30, "size": 4000000,
     "license": "CC0-1.0", "credit": "WallVue",
     "source": "https://example.com/source",
     "thumbnail": "https://example.com/thumbs/\(id).jpg",
     "files": ["https://example.com/a/\(id).mp4", "https://mirror.example.com/\(id).mp4"]\(extra)}
    """
}

private func indexJSON(_ entries: [String]) -> Data {
    Data("{\"version\": 1, \"updated\": \"2026-11-17\", \"wallpapers\": [\(entries.joined(separator: ","))]}".utf8)
}

final class CatalogueFormatTests: XCTestCase {
    func testReadsAnEntry() throws {
        let entries = try Catalogue.entries(inIndexJSON: indexJSON([entryJSON("aurora-veil", title: "Aurora Veil")]))
        let entry = try XCTUnwrap(entries.first)
        XCTAssertEqual(entry.id, "aurora-veil")
        XCTAssertEqual(entry.title, "Aurora Veil")
        XCTAssertEqual(entry.kind, .video)
        XCTAssertEqual(entry.size, 4_000_000)
        XCTAssertEqual(entry.files.map(\.host), ["example.com", "mirror.example.com"])
        XCTAssertEqual(entry.thumbnail?.lastPathComponent, "aurora-veil.jpg")
        XCTAssertTrue(entry.is4K)
        XCTAssertTrue(entry.detailLabel.hasPrefix("3840×2160 · "))
        XCTAssertTrue(entry.detailLabel.hasSuffix(" · 0:16"))
    }

    func testABrokenEntryIsSkippedNotFatal() throws {
        let noLicence = "{\"id\": \"x\", \"title\": \"X\", \"credit\": \"Someone\", \"files\": [\"https://example.com/x.mp4\"]}"
        let noFiles = "{\"id\": \"y\", \"title\": \"Y\", \"license\": \"CC0-1.0\", \"credit\": \"Someone\", \"files\": []}"
        let entries = try Catalogue.entries(inIndexJSON: indexJSON([noLicence, entryJSON("good"), noFiles, "42"]))
        XCTAssertEqual(entries.map(\.id), ["good"])
    }

    func testUnknownFieldsAndMissingDetailsAreTolerated() throws {
        let minimal = "{\"id\": \"m\", \"title\": \"M\", \"license\": \"CC-BY-4.0\", \"credit\": \"Jane\", \"files\": [\"https://example.com/m.mov\"]}"
        let future = entryJSON("f", extra: ", \"palette\": [\"#000\"], \"added\": \"2027-01-01\"")
        let entries = try Catalogue.entries(inIndexJSON: indexJSON([minimal, future]))
        XCTAssertEqual(entries.map(\.id), ["m", "f"])
        XCTAssertEqual(entries[0].category, "Others")
        XCTAssertEqual(entries[0].kind, .video)
        XCTAssertNil(entries[0].thumbnail)
    }

    func testRepeatedIDsKeepTheFirst() throws {
        let entries = try Catalogue.entries(inIndexJSON: indexJSON([entryJSON("a", title: "First"), entryJSON("a", title: "Second")]))
        XCTAssertEqual(entries.map(\.title), ["First"])
    }

    func testRubbishIsAnError() {
        XCTAssertThrowsError(try Catalogue.entries(inIndexJSON: Data("<html>Not Found</html>".utf8)))
    }
}

final class DownloadLimitTests: XCTestCase {
    private func downloaded(_ title: String, mb: Int64, playedDaysAgo: Double?, favorite: Bool = false) -> Wallpaper {
        Wallpaper(
            title: title, fileName: "\(title).mp4", origin: .catalogue, width: 3840, height: 2160,
            fileSize: mb * 1_000_000, isFavorite: favorite,
            dateAdded: Date(timeIntervalSinceNow: -100 * 86400),
            lastPlayed: playedDaysAgo.map { Date(timeIntervalSinceNow: -$0 * 86400) }
        )
    }

    func testNothingLeavesWhileThereIsRoom() {
        let have = [downloaded("a", mb: 300, playedDaysAgo: 1)]
        XCTAssertEqual(Catalogue.evictions(toFit: 500_000_000, limit: 1_000_000_000, downloaded: have, keeping: []), [])
    }

    func testOldestPlayedLeavesFirstAndOnlyAsManyAsNeeded() throws {
        let old = downloaded("old", mb: 400, playedDaysAgo: 30)
        let never = downloaded("never", mb: 300, playedDaysAgo: nil)      // counts from when it was added: oldest
        let recent = downloaded("recent", mb: 300, playedDaysAgo: 1)
        let leaving = try XCTUnwrap(Catalogue.evictions(
            toFit: 400_000_000, limit: 1_000_000_000, downloaded: [recent, old, never], keeping: []
        ))
        XCTAssertEqual(leaving.map(\.title), ["never", "old"])
    }

    func testFavoritesAndWhatIsOnScreenAreNeverRemoved() {
        let favorite = downloaded("favorite", mb: 600, playedDaysAgo: 90, favorite: true)
        let showing = downloaded("showing", mb: 300, playedDaysAgo: 60)
        XCTAssertNil(Catalogue.evictions(
            toFit: 400_000_000, limit: 1_000_000_000, downloaded: [favorite, showing], keeping: [showing.id]
        ))
    }

    func testSomethingBiggerThanTheLimitNeverFits() {
        XCTAssertNil(Catalogue.evictions(toFit: 3_000_000_000, limit: 2_000_000_000, downloaded: [], keeping: []))
    }
}

@MainActor
final class CatalogueStoreTests: XCTestCase {
    private var folder: URL!

    override func setUp() async throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("wallvue-catalogue-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bundled/thumbnails"), withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func store(remote: URL?) -> CatalogueStore {
        CatalogueStore(
            remote: remote, bundled: folder.appendingPathComponent("bundled"),
            cacheFile: folder.appendingPathComponent("cache.json"), thumbnails: folder.appendingPathComponent("thumbs")
        )
    }

    func testShowsTheListThatShipsWithTheAppBeforeAnyRefresh() throws {
        try indexJSON([entryJSON("a"), entryJSON("b")]).write(to: folder.appendingPathComponent("bundled/index.json"))
        try Data("jpg".utf8).write(to: folder.appendingPathComponent("bundled/thumbnails/a.jpg"))
        let catalogue = store(remote: nil)
        XCTAssertEqual(catalogue.entries.map(\.id), ["a", "b"])
        XCTAssertEqual(catalogue.thumbnailFile(for: catalogue.entries[0])?.lastPathComponent, "a.jpg")
    }

    /// The promise made to users: a wallpaper added to the online list shows
    /// up in a copy of the app that shipped without it.
    func testAWallpaperAddedOnlineAppearsAfterARefreshAndIsRemembered() async throws {
        try indexJSON([entryJSON("a")]).write(to: folder.appendingPathComponent("bundled/index.json"))
        let online = folder.appendingPathComponent("online.json")
        try indexJSON([entryJSON("a"), entryJSON("brand-new")]).write(to: online)

        let catalogue = store(remote: online)
        XCTAssertEqual(catalogue.entries.map(\.id), ["a"])
        await catalogue.refresh()
        XCTAssertEqual(catalogue.entries.map(\.id), ["a", "brand-new"])
        XCTAssertFalse(catalogue.refreshFailed)

        // The next launch starts from the saved list, even offline.
        XCTAssertEqual(store(remote: nil).entries.map(\.id), ["a", "brand-new"])
    }

    func testAFailedRefreshKeepsWhatWasShown() async throws {
        try indexJSON([entryJSON("a")]).write(to: folder.appendingPathComponent("bundled/index.json"))
        let broken = folder.appendingPathComponent("broken.json")
        try Data("<html>Not Found</html>".utf8).write(to: broken)
        let catalogue = store(remote: broken)
        await catalogue.refresh()
        XCTAssertTrue(catalogue.refreshFailed)
        XCTAssertEqual(catalogue.entries.map(\.id), ["a"])
    }

    func testARecentRefreshIsNotRepeatedUnlessForced() async throws {
        let online = folder.appendingPathComponent("online.json")
        try indexJSON([entryJSON("a")]).write(to: online)
        let catalogue = store(remote: online)
        await catalogue.refresh()
        try indexJSON([entryJSON("a"), entryJSON("b")]).write(to: online)
        await catalogue.refresh()
        XCTAssertEqual(catalogue.entries.count, 1)
        await catalogue.refresh(force: true)
        XCTAssertEqual(catalogue.entries.count, 2)
    }

    func testDownloadTriesTheNextLocationWhenOneFails() async throws {
        let real = folder.appendingPathComponent("real.mp4")
        try Data("video bytes".utf8).write(to: real)
        let missing = folder.appendingPathComponent("missing.mp4")
        let json = "{\"id\": \"v\", \"title\": \"V\", \"license\": \"CC0-1.0\", \"credit\": \"WallVue\", \"files\": [\"\(missing.absoluteString)\", \"\(real.absoluteString)\"]}"
        let online = folder.appendingPathComponent("online.json")
        try indexJSON([json]).write(to: online)
        let catalogue = store(remote: online)
        await catalogue.refresh()
        let entry = try XCTUnwrap(catalogue.entries.first)

        let file = try await catalogue.download(entry)
        defer { try? FileManager.default.removeItem(at: file) }
        XCTAssertEqual(try Data(contentsOf: file), Data("video bytes".utf8))
        XCTAssertNil(catalogue.progress["v"], "progress is cleared when the download ends")
    }
}
