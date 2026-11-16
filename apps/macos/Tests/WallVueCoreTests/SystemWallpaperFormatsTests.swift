import XCTest
@testable import WallVueCore

final class AerialManifestTests: XCTestCase {
    private let video = URL(fileURLWithPath: "/tmp/aerials/videos/AAA.mov")
    private let thumb = URL(fileURLWithPath: "/tmp/aerials/thumbnails/AAA.png")

    private var appleEntries: [String: Any] {
        [
            "version": 1,
            "localizationVersion": "23J-1",
            "initialAssetCount": 4,
            "categories": [["id": "APPLE-CAT", "localizedNameKey": "Landscape", "subcategories": [[String: Any]]()] as [String: Any]],
            "assets": [["id": "APPLE-1", "categories": ["APPLE-CAT"], "url-4K-SDR-240FPS": "https://example.com/a.mov"] as [String: Any]],
        ]
    }

    func testAddsOneCategoryAndAssetAndKeepsApples() {
        let result = AerialManifest.settingAsset(id: "AAA", name: "Aurora", videoURL: video, thumbnailURL: thumb, in: appleEntries)
        let categories = result["categories"] as! [[String: Any]]
        let assets = result["assets"] as! [[String: Any]]
        XCTAssertEqual(categories.map { $0["id"] as? String }, ["APPLE-CAT", AerialManifest.categoryID])
        XCTAssertEqual(assets.map { $0["id"] as? String }, ["APPLE-1", "AAA"])
        XCTAssertEqual(result["localizationVersion"] as? String, "23J-1")
        XCTAssertEqual(result["initialAssetCount"] as? Int, 4)

        let ours = assets[1]
        XCTAssertEqual(ours["url-4K-SDR-240FPS"] as? String, video.absoluteString)
        XCTAssertEqual(ours["previewImage"] as? String, thumb.absoluteString)
        XCTAssertEqual(ours["categories"] as? [String], [AerialManifest.categoryID])
        XCTAssertEqual(ours["subcategories"] as? [String], [AerialManifest.subcategoryID])
        // Same field set as Apple's own assets on macOS 26.
        XCTAssertEqual(Set(ours.keys), [
            "accessibilityLabel", "categories", "id", "includeInShuffle", "localizedNameKey", "pointsOfInterest",
            "preferredOrder", "previewImage", "shotID", "showInTopLevel", "subcategories", "url-4K-SDR-240FPS",
        ])
        let category = categories[1]
        XCTAssertEqual(Set(category.keys), [
            "id", "localizedDescriptionKey", "localizedNameKey", "preferredOrder", "previewImage",
            "representativeAssetID", "subcategories",
        ])
        let sub = (category["subcategories"] as! [[String: Any]])[0]
        XCTAssertEqual(Set(sub.keys), [
            "id", "localizedDescriptionKey", "localizedNameKey", "preferredOrder", "previewImage", "representativeAssetID",
        ])
    }

    func testSettingAgainReplacesTheOldAsset() {
        let first = AerialManifest.settingAsset(id: "AAA", name: "Aurora", videoURL: video, thumbnailURL: thumb, in: appleEntries)
        let second = AerialManifest.settingAsset(id: "BBB", name: "Bloom", videoURL: video, thumbnailURL: thumb, in: first)
        XCTAssertEqual(AerialManifest.wallVueAssetIDs(in: second), ["BBB"])
        XCTAssertEqual((second["categories"] as! [[String: Any]]).count, 2)
    }

    func testRemovingRestoresApplesExactly() throws {
        let added = AerialManifest.settingAsset(id: "AAA", name: "Aurora", videoURL: video, thumbnailURL: thumb, in: appleEntries)
        let removed = AerialManifest.removingWallVue(from: added)
        let a = try JSONSerialization.data(withJSONObject: removed, options: [.sortedKeys])
        let b = try JSONSerialization.data(withJSONObject: appleEntries, options: [.sortedKeys])
        XCTAssertEqual(a, b)
    }

    func testResultIsValidJSONEvenFromNothing() throws {
        let result = AerialManifest.settingAsset(id: "AAA", name: "Aurora", videoURL: video, thumbnailURL: thumb, in: [:])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(result))
        XCTAssertEqual(result["version"] as? Int, 1)
    }
}

final class WallpaperStoreTests: XCTestCase {
    func testSetsEveryDisplayAndSpaceAndKeepsUnknownKeys() throws {
        let old: [String: Any] = ["Type": "individual"]
        let store: [String: Any] = [
            "SystemDefault": old,
            "AllSpacesAndDisplays": old,
            "Displays": ["D1": old, "D2": old],
            "Spaces": ["S1": ["Default": old, "Displays": ["D1": old]], "S2": ["Displays": [String: Any]()]],
            "SomethingNew": 42,
        ]
        let result = try WallpaperStore.settingAerial(assetID: "AAA", in: store)
        XCTAssertEqual(WallpaperStore.currentAerialAssetID(in: result), "AAA")
        XCTAssertEqual(result["SomethingNew"] as? Int, 42)

        func isOurs(_ value: Any?) -> Bool {
            guard let entry = value as? [String: Any] else { return false }
            return WallpaperStore.currentAerialAssetID(in: ["AllSpacesAndDisplays": entry]) == "AAA"
        }
        let displays = result["Displays"] as! [String: Any]
        XCTAssertTrue(isOurs(displays["D1"]) && isOurs(displays["D2"]))
        let spaces = result["Spaces"] as! [String: Any]
        let s1 = spaces["S1"] as! [String: Any]
        XCTAssertTrue(isOurs(s1["Default"]))
        XCTAssertTrue(isOurs((s1["Displays"] as! [String: Any])["D1"]))
        // A Space without its own default does not gain one.
        XCTAssertNil((spaces["S2"] as! [String: Any])["Default"])
    }

    func testResultSerialisesAsBinaryPropertyList() throws {
        let result = try WallpaperStore.settingAerial(assetID: "AAA", in: [:])
        let data = try PropertyListSerialization.data(fromPropertyList: result, format: .binary, options: 0)
        let back = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        XCTAssertEqual(WallpaperStore.currentAerialAssetID(in: back), "AAA")
    }

    func testNonAerialStoreReportsNoAsset() {
        XCTAssertNil(WallpaperStore.currentAerialAssetID(in: ["AllSpacesAndDisplays": ["Type": "individual"]]))
        XCTAssertNil(WallpaperStore.currentAerialAssetID(in: [:]))
    }

    /// Runs the edits against copies of this Mac's real files when
    /// WALLVUE_REAL_WALLPAPER_COPY points at a folder holding
    /// `entries.json` and `Index.plist`. Nothing is written back.
    func testAgainstCopiesOfRealFiles() throws {
        guard let folder = ProcessInfo.processInfo.environment["WALLVUE_REAL_WALLPAPER_COPY"] else {
            throw XCTSkip("Set WALLVUE_REAL_WALLPAPER_COPY to run against real files")
        }
        let base = URL(fileURLWithPath: folder)
        let entries = try JSONSerialization.jsonObject(with: Data(contentsOf: base.appendingPathComponent("entries.json"))) as! [String: Any]
        let store = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: base.appendingPathComponent("Index.plist")), format: nil
        ) as! [String: Any]

        let appleAssets = (entries["assets"] as! [[String: Any]])
        let video = URL(fileURLWithPath: "/tmp/x/AAA.mov"), thumb = URL(fileURLWithPath: "/tmp/x/AAA.png")
        let edited = AerialManifest.settingAsset(id: "AAA", name: "Test", videoURL: video, thumbnailURL: thumb, in: entries)
        let editedAssets = edited["assets"] as! [[String: Any]]
        XCTAssertEqual(editedAssets.count, appleAssets.count + 1)
        // Our asset has exactly the keys a real Apple asset has.
        XCTAssertEqual(Set(editedAssets.last!.keys), Set(appleAssets[0].keys))
        XCTAssertEqual(Set(edited.keys), Set(entries.keys))
        _ = try JSONSerialization.data(withJSONObject: edited)

        let restored = AerialManifest.removingWallVue(from: edited)
        XCTAssertEqual(
            try JSONSerialization.data(withJSONObject: restored, options: [.sortedKeys]),
            try JSONSerialization.data(withJSONObject: entries, options: [.sortedKeys])
        )

        let newStore = try WallpaperStore.settingAerial(assetID: "AAA", in: store)
        XCTAssertEqual(Set(newStore.keys), Set(store.keys).union(["SystemDefault", "AllSpacesAndDisplays"]))
        let data = try PropertyListSerialization.data(fromPropertyList: newStore, format: .binary, options: 0)
        let back = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        XCTAssertEqual(WallpaperStore.currentAerialAssetID(in: back), "AAA")
    }
}
