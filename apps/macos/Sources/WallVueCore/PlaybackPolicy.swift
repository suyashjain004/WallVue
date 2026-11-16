import Foundation

/// Everything that can influence whether one display's wallpaper should be
/// decoding video right now.
public struct PlaybackEnvironment: Equatable, Sendable {
    public var userPaused = false
    public var displayAsleep = false
    public var sessionLocked = false
    /// False when windows fully cover the desktop on this display.
    public var desktopVisible = true
    public var onBattery = false
    public var lowPowerMode = false
    /// Thermal state is `serious` or `critical`.
    public var thermallyConstrained = false

    public init() {}
}

/// The user's preferences for when to hold the frame.
public struct PlaybackRules: Equatable, Sendable {
    public var pauseWhenCovered = true
    public var pauseOnBattery = false
    public var pauseInLowPowerMode = true
    public var pauseWhenHot = true

    public init() {}
}

public enum PauseReason: String, Equatable, Sendable {
    case user, displayAsleep, locked, covered, battery, lowPowerMode, thermal

    public var label: String {
        switch self {
        case .user: return "Paused"
        case .displayAsleep: return "Display asleep"
        case .locked: return "Screen locked"
        case .covered: return "Paused — desktop covered"
        case .battery: return "Paused — on battery"
        case .lowPowerMode: return "Paused — Low Power Mode"
        case .thermal: return "Paused — Mac is running hot"
        }
    }
}

public enum PlaybackDecision: Equatable, Sendable {
    case play
    case pause(PauseReason)

    public var isPlaying: Bool { self == .play }
}

/// Pure decision function — the single place that answers "should this
/// surface play?". Kept free of AppKit so it is trivially unit-testable and
/// can be reused by a future system wallpaper extension.
public enum PlaybackPolicy {
    public static func decide(_ env: PlaybackEnvironment, rules: PlaybackRules) -> PlaybackDecision {
        // Hard stops first: nothing can be seen, so never decode.
        if env.displayAsleep { return .pause(.displayAsleep) }
        if env.sessionLocked { return .pause(.locked) }
        // Explicit user intent beats every automatic rule.
        if env.userPaused { return .pause(.user) }
        // Power and heat before occlusion, so the UI reports the cause the
        // user can actually act on.
        if rules.pauseWhenHot && env.thermallyConstrained { return .pause(.thermal) }
        if rules.pauseInLowPowerMode && env.lowPowerMode { return .pause(.lowPowerMode) }
        if rules.pauseOnBattery && env.onBattery { return .pause(.battery) }
        if rules.pauseWhenCovered && !env.desktopVisible { return .pause(.covered) }
        return .play
    }
}
