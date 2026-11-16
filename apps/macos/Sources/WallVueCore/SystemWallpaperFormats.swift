import Foundation

// Pure edits to the two files macOS 26 uses for Aerial wallpapers:
//
//   ~/Library/Application Support/com.apple.wallpaper/aerials/manifest/entries.json
//   ~/Library/Application Support/com.apple.wallpaper/Store/Index.plist
//
// macOS plays Aerials on the Lock Screen and as the screen saver. Listing a
// video of ours in the manifest and pointing the store at it makes macOS play
// that video there too. The formats are undocumented; the field set below
// follows the approach published in LivePaper (MIT, see THIRD_PARTY_NOTICES).
// Everything here is side-effect free so it can be tested against real files.

public enum AerialManifest {
    /// Fixed identifiers for WallVue's own section in the Aerials list.
    public static let categoryID = "3F0A7C1E-5D2B-4E8A-9C61-57A11A000001"
    public static let subcategoryID = "3F0A7C1E-5D2B-4E8A-9C61-57A11A000002"
    static let shotID = "WALLVUE_CUSTOM"

    /// Returns `entries` with WallVue's category present and holding exactly
    /// one asset: the given video. Apple's own entries are left untouched.
    public static func settingAsset(
        id assetID: String,
        name: String,
        videoURL: URL,
        thumbnailURL: URL,
        in entries: [String: Any]
    ) -> [String: Any] {
        var result = removingWallVue(from: entries)
        if result["version"] == nil { result["version"] = 1 }
        var categories = result["categories"] as? [[String: Any]] ?? []
        var assets = result["assets"] as? [[String: Any]] ?? []

        let thumbnail = thumbnailURL.absoluteString
        // Every field is required by the system's decoder; a missing one makes
        // macOS discard the whole manifest.
        categories.append([
            "id": categoryID,
            "localizedNameKey": AppInfo.name,
            "localizedDescriptionKey": "\(AppInfo.name) wallpaper",
            "preferredOrder": 999,
            "representativeAssetID": assetID,
            "previewImage": thumbnail,
            "subcategories": [[
                "id": subcategoryID,
                "localizedNameKey": AppInfo.name,
                "localizedDescriptionKey": "\(AppInfo.name) wallpaper",
                "preferredOrder": 0,
                "previewImage": thumbnail,
                "representativeAssetID": assetID,
            ] as [String: Any]],
        ])
        assets.append([
            "id": assetID,
            "localizedNameKey": name,
            "accessibilityLabel": name,
            "shotID": shotID,
            "showInTopLevel": true,
            "includeInShuffle": false,
            "preferredOrder": 0,
            "categories": [categoryID],
            "subcategories": [subcategoryID],
            "url-4K-SDR-240FPS": videoURL.absoluteString,
            "previewImage": thumbnail,
            "pointsOfInterest": ["0": "WALLVUE_0"],
        ])

        result["categories"] = categories
        result["assets"] = assets
        return result
    }

    /// Returns `entries` without WallVue's category and assets.
    public static func removingWallVue(from entries: [String: Any]) -> [String: Any] {
        var result = entries
        if let categories = entries["categories"] as? [[String: Any]] {
            result["categories"] = categories.filter { ($0["id"] as? String) != categoryID }
        }
        if let assets = entries["assets"] as? [[String: Any]] {
            result["assets"] = assets.filter { asset in
                !((asset["categories"] as? [String])?.contains(categoryID) ?? false)
            }
        }
        return result
    }

    /// IDs of the assets WallVue has registered.
    public static func wallVueAssetIDs(in entries: [String: Any]) -> [String] {
        (entries["assets"] as? [[String: Any]] ?? []).compactMap { asset in
            guard (asset["categories"] as? [String])?.contains(categoryID) == true else { return nil }
            return asset["id"] as? String
        }
    }
}

public enum WallpaperStore {
    static let aerialsProvider = "com.apple.wallpaper.choice.aerials"

    /// Returns `store` with every display and Space set to the Aerial
    /// `assetID`. Unknown keys are preserved.
    public static func settingAerial(assetID: String, in store: [String: Any], now: Date = Date()) throws -> [String: Any] {
        let configuration = try PropertyListSerialization.data(
            fromPropertyList: ["assetID": assetID], format: .binary, options: 0
        )
        let entry: [String: Any] = [
            "Type": "linked",
            "Linked": [
                "Content": [
                    "Choices": [[
                        "Provider": aerialsProvider,
                        "Files": [Any](),
                        "Configuration": configuration,
                    ] as [String: Any]],
                ] as [String: Any],
                "LastSet": now,
                "LastUse": now,
            ] as [String: Any],
        ]

        var result = store
        result["SystemDefault"] = entry
        // The global entry is what the Lock Screen follows on every display.
        result["AllSpacesAndDisplays"] = entry

        if var displays = store["Displays"] as? [String: Any] {
            for key in displays.keys { displays[key] = entry }
            result["Displays"] = displays
        }
        if var spaces = store["Spaces"] as? [String: Any] {
            for (spaceKey, value) in spaces {
                guard var space = value as? [String: Any] else { continue }
                if space["Default"] != nil { space["Default"] = entry }
                if var spaceDisplays = space["Displays"] as? [String: Any] {
                    for key in spaceDisplays.keys { spaceDisplays[key] = entry }
                    space["Displays"] = spaceDisplays
                }
                spaces[spaceKey] = space
            }
            result["Spaces"] = spaces
        }
        return result
    }

    /// The Aerial asset the store currently points at, if it is an Aerial.
    public static func currentAerialAssetID(in store: [String: Any]) -> String? {
        guard let entry = store["AllSpacesAndDisplays"] as? [String: Any] ?? store["SystemDefault"] as? [String: Any],
              let linked = entry["Linked"] as? [String: Any],
              let content = linked["Content"] as? [String: Any],
              let choice = (content["Choices"] as? [[String: Any]])?.first,
              (choice["Provider"] as? String) == aerialsProvider,
              let data = choice["Configuration"] as? Data,
              let configuration = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return configuration["assetID"] as? String
    }
}
