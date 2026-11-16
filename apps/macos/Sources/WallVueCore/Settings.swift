import Foundation

/// UserDefaults keys. SwiftUI views bind to these with `@AppStorage`; the
/// engine reads them through `SettingsSnapshot`.
public enum SettingsKey {
    // General
    public static let showMenuBarIcon = "showMenuBarIcon"
    public static let playPreviewsWhileBrowsing = "playPreviewsWhileBrowsing"
    public static let restoreOnLaunch = "restoreOnLaunch"
    public static let hasCompletedOnboarding = "hasCompletedOnboarding"
    // Wallpaper
    public static let playbackMode = "playbackMode"
    public static let scaling = "scaling"
    public static let playbackRate = "playbackRate"
    public static let dimAmount = "dimAmount"
    public static let blurAmount = "blurAmount"
    public static let shuffleEnabled = "shuffleEnabled"
    public static let shuffleSource = "shuffleSource"
    public static let shuffleInterval = "shuffleInterval"
    public static let scheduleEnabled = "scheduleEnabled"
    // Lock Screen
    public static let syncStillToSystem = "syncStillToSystem"
    public static let liveLockScreen = "liveLockScreen"
    public static let playOnlyOnLockScreen = "playOnlyOnLockScreen"
    public static let playWhileLocked = "playWhileLocked"
    // Sound
    public static let muted = "muted"
    public static let volume = "volume"
    // Battery & Performance
    public static let pauseOnBattery = "pauseOnBattery"
    public static let pauseInLowPowerMode = "pauseInLowPowerMode"
    public static let pauseWhenCovered = "pauseWhenCovered"
    public static let pauseWhenHot = "pauseWhenHot"
    // Storage
    public static let downloadLimitGB = "downloadLimitGB"
}

public enum ScalingMode: String, CaseIterable, Identifiable, Sendable {
    case fill, fit, stretch

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .fill: return "Fill screen"
        case .fit: return "Fit to screen"
        case .stretch: return "Stretch"
        }
    }
}

/// Who plays the wallpaper.
public enum PlaybackMode: String, CaseIterable, Identifiable, Sendable {
    /// macOS plays it through the wallpaper extension (desktop, Lock Screen
    /// and screen saver; keeps playing with the app closed). macOS 26+.
    case system
    /// The app plays it in its own desktop window while it is open.
    case app

    public var id: String { rawValue }
}

public enum ShuffleSource: String, CaseIterable, Identifiable, Sendable {
    case favorites, library

    public var id: String { rawValue }
    public var label: String { self == .favorites ? "Favorites" : "Whole Library" }
}

public enum SettingsDefaults {
    public static let values: [String: Any] = [
        SettingsKey.showMenuBarIcon: true,
        SettingsKey.playPreviewsWhileBrowsing: false,
        SettingsKey.restoreOnLaunch: true,
        SettingsKey.hasCompletedOnboarding: false,
        SettingsKey.playbackMode: PlaybackMode.app.rawValue,
        SettingsKey.scaling: ScalingMode.fill.rawValue,
        SettingsKey.playbackRate: 1.0,
        SettingsKey.dimAmount: 0.0,
        SettingsKey.blurAmount: 0.0,
        SettingsKey.shuffleEnabled: false,
        SettingsKey.shuffleSource: ShuffleSource.favorites.rawValue,
        SettingsKey.shuffleInterval: 3600.0,
        SettingsKey.scheduleEnabled: false,
        SettingsKey.syncStillToSystem: true,
        SettingsKey.liveLockScreen: false,
        SettingsKey.playOnlyOnLockScreen: false,
        SettingsKey.playWhileLocked: true,
        SettingsKey.muted: true,
        SettingsKey.volume: 0.5,
        SettingsKey.pauseOnBattery: false,
        SettingsKey.pauseInLowPowerMode: true,
        SettingsKey.pauseWhenCovered: true,
        SettingsKey.pauseWhenHot: true,
        SettingsKey.downloadLimitGB: 10,
    ]

    /// Call once at launch, before anything reads settings.
    public static func register(in defaults: UserDefaults = .standard) {
        defaults.register(defaults: values)
    }
}

/// An immutable read of all settings the engine cares about.
public struct SettingsSnapshot: Equatable, Sendable {
    public var muted: Bool
    public var volume: Double
    public var playbackRate: Double
    public var scaling: ScalingMode
    public var dimAmount: Double
    public var blurAmount: Double
    public var rules: PlaybackRules
    public var syncStillToSystem: Bool
    public var liveLockScreen: Bool
    public var restoreOnLaunch: Bool
    public var shuffleEnabled: Bool
    public var shuffleSource: ShuffleSource
    public var shuffleInterval: Double
    public var scheduleEnabled: Bool

    public static func load(from defaults: UserDefaults = .standard) -> SettingsSnapshot {
        var rules = PlaybackRules()
        rules.pauseWhenCovered = defaults.bool(forKey: SettingsKey.pauseWhenCovered)
        rules.pauseOnBattery = defaults.bool(forKey: SettingsKey.pauseOnBattery)
        rules.pauseInLowPowerMode = defaults.bool(forKey: SettingsKey.pauseInLowPowerMode)
        rules.pauseWhenHot = defaults.bool(forKey: SettingsKey.pauseWhenHot)

        func clamp(_ value: Double, _ low: Double, _ high: Double) -> Double { min(max(value, low), high) }
        let rate = defaults.double(forKey: SettingsKey.playbackRate)
        let interval = defaults.double(forKey: SettingsKey.shuffleInterval)

        return SettingsSnapshot(
            muted: defaults.bool(forKey: SettingsKey.muted),
            volume: clamp(defaults.double(forKey: SettingsKey.volume), 0, 1),
            playbackRate: rate > 0 ? clamp(rate, 0.25, 2.0) : 1.0,
            scaling: ScalingMode(rawValue: defaults.string(forKey: SettingsKey.scaling) ?? "") ?? .fill,
            dimAmount: clamp(defaults.double(forKey: SettingsKey.dimAmount), 0, 0.8),
            blurAmount: clamp(defaults.double(forKey: SettingsKey.blurAmount), 0, 1),
            rules: rules,
            syncStillToSystem: defaults.bool(forKey: SettingsKey.syncStillToSystem),
            liveLockScreen: defaults.bool(forKey: SettingsKey.liveLockScreen),
            restoreOnLaunch: defaults.bool(forKey: SettingsKey.restoreOnLaunch),
            shuffleEnabled: defaults.bool(forKey: SettingsKey.shuffleEnabled),
            shuffleSource: ShuffleSource(rawValue: defaults.string(forKey: SettingsKey.shuffleSource) ?? "") ?? .favorites,
            shuffleInterval: interval >= 60 ? interval : 3600,
            scheduleEnabled: defaults.bool(forKey: SettingsKey.scheduleEnabled)
        )
    }
}
