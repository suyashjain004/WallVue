import XCTest
@testable import WallVueCore

final class PlaybackPolicyTests: XCTestCase {
    func testPlaysByDefault() {
        XCTAssertEqual(PlaybackPolicy.decide(PlaybackEnvironment(), rules: PlaybackRules()), .play)
    }

    func testSleepAndLockAlwaysPause() {
        var rules = PlaybackRules()
        rules.pauseWhenCovered = false
        rules.pauseInLowPowerMode = false
        rules.pauseWhenHot = false

        var asleep = PlaybackEnvironment()
        asleep.displayAsleep = true
        XCTAssertEqual(PlaybackPolicy.decide(asleep, rules: rules), .pause(.displayAsleep))

        var locked = PlaybackEnvironment()
        locked.sessionLocked = true
        XCTAssertEqual(PlaybackPolicy.decide(locked, rules: rules), .pause(.locked))
    }

    func testUserPauseWinsOverAutomaticRules() {
        var env = PlaybackEnvironment()
        env.userPaused = true
        env.onBattery = true
        var rules = PlaybackRules()
        rules.pauseOnBattery = true
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: rules), .pause(.user))
    }

    func testBatteryRuleIsOptIn() {
        var env = PlaybackEnvironment()
        env.onBattery = true
        var rules = PlaybackRules()
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: rules), .play)
        rules.pauseOnBattery = true
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: rules), .pause(.battery))
    }

    func testCoveredDesktopPausesUnlessDisabled() {
        var env = PlaybackEnvironment()
        env.desktopVisible = false
        var rules = PlaybackRules()
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: rules), .pause(.covered))
        rules.pauseWhenCovered = false
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: rules), .play)
    }

    func testPowerReasonReportedBeforeOcclusion() {
        var env = PlaybackEnvironment()
        env.desktopVisible = false
        env.lowPowerMode = true
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: PlaybackRules()), .pause(.lowPowerMode))
    }
}

final class EngineStateTests: XCTestCase {
    func testAssignmentOverridesDefault() {
        var state = EngineState()
        let everywhere = UUID(), external = UUID()
        state.defaultWallpaperID = everywhere
        state.assignments["display-2"] = external
        XCTAssertEqual(state.wallpaperID(forDisplay: "display-1"), everywhere)
        XCTAssertEqual(state.wallpaperID(forDisplay: "display-2"), external)
    }

    func testPruneDropsDeletedWallpapers() {
        var state = EngineState()
        let kept = UUID(), deleted = UUID()
        state.defaultWallpaperID = deleted
        state.assignments = ["a": kept, "b": deleted]
        state.prune(keeping: [kept])
        XCTAssertNil(state.defaultWallpaperID)
        XCTAssertEqual(state.assignments, ["a": kept])
        XCTAssertTrue(state.isActive)
    }

    func testRoundTripsThroughDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("state-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var state = EngineState()
        state.defaultWallpaperID = UUID()
        state.originalDesktopImages["a"] = "/System/Library/Desktop Pictures/Example.heic"
        try JSONEncoder().encode(state).write(to: url)
        XCTAssertEqual(EngineState.load(from: url), state)
    }
}

final class WallpaperLabelTests: XCTestCase {
    private func make(_ w: Int, _ h: Int, duration: Double = 30) -> Wallpaper {
        Wallpaper(title: "t", fileName: "f.mp4", width: w, height: h, duration: duration, fileSize: 26_214_400)
    }

    func testResolutionFlags() {
        XCTAssertTrue(make(3840, 2160).is4K)
        XCTAssertFalse(make(2560, 1440).is4K)
        XCTAssertTrue(make(2160, 3840).is4K)          // portrait
        XCTAssertTrue(make(5120, 2160).isUltrawide)
        XCTAssertFalse(make(3840, 2160).isUltrawide)
    }

    func testDetailLabel() {
        let label = make(3840, 2160, duration: 95.4).detailLabel
        XCTAssertTrue(label.hasPrefix("3840×2160 · "))
        XCTAssertTrue(label.hasSuffix(" · 1:35"))
    }

    func testStillHasNoDuration() {
        let still = Wallpaper(title: "t", fileName: "f.png", kind: .still, width: 100, height: 50)
        XCTAssertFalse(still.detailLabel.contains(":"))
        XCTAssertEqual(still.stillURL, still.fileURL)
    }

    func testSorting() {
        var a = make(10, 10); a.title = "beta"; a.playCount = 5
        var b = make(10, 10); b.title = "Alpha"; b.playCount = 1; b.fileSize = 99_000_000
        XCTAssertEqual(LibrarySort.mostPlayed.sorted([b, a]).first?.id, a.id)
        XCTAssertEqual(LibrarySort.name.sorted([a, b]).first?.id, b.id)
        XCTAssertEqual(LibrarySort.largest.sorted([a, b]).first?.id, b.id)
    }

    @MainActor
    func testPrettyTitle() {
        let url = URL(fileURLWithPath: "/tmp/misty_forest-4k__loop.mp4")
        XCTAssertEqual(LibraryStore.prettyTitle(from: url), "misty forest 4k loop")
    }
}

final class ScheduleTests: XCTestCase {
    func testDefaultSlotsAndLabels() {
        let schedule = DaySchedule()
        XCTAssertEqual(schedule.slots.map(\.minutes), [420, 720, 1080, 1320])
        XCTAssertEqual(schedule.slots.map(\.periodLabel), ["Morning", "Afternoon", "Evening", "Night"])
        XCTAssertEqual(DaySchedule.periodLabel(forMinutes: 150), "Late Night")
    }

    func testClockFormatting() {
        XCTAssertEqual(ScheduleSlot(minutes: 0).clock.time, "12:00")
        XCTAssertEqual(ScheduleSlot(minutes: 0).clock.meridiem, "AM")
        XCTAssertEqual(ScheduleSlot(minutes: 16 * 60 + 32).clock.time, "4:32")
        XCTAssertEqual(ScheduleSlot(minutes: 16 * 60 + 32).clock.meridiem, "PM")
    }

    func testActiveSlotPicksLatestStartedAndWrapsOvernight() {
        let morning = UUID(), night = UUID()
        var schedule = DaySchedule()
        schedule.slots[0].wallpaperID = morning   // 7:00
        schedule.slots[3].wallpaperID = night     // 22:00
        XCTAssertEqual(schedule.activeSlot(atMinutes: 8 * 60)?.wallpaperID, morning)
        XCTAssertEqual(schedule.activeSlot(atMinutes: 15 * 60)?.wallpaperID, morning) // empty slots skipped
        XCTAssertEqual(schedule.activeSlot(atMinutes: 23 * 60)?.wallpaperID, night)
        XCTAssertEqual(schedule.activeSlot(atMinutes: 3 * 60)?.wallpaperID, night)    // before first slot
    }

    func testEmptyScheduleHasNoActiveSlot() {
        XCTAssertNil(DaySchedule().activeSlot(atMinutes: 600))
    }

    func testUpsertKeepsOrderAndPruneClears() {
        var schedule = DaySchedule(slots: [])
        let gone = UUID()
        schedule.upsert(ScheduleSlot(minutes: 900, wallpaperID: gone))
        schedule.upsert(ScheduleSlot(minutes: 300))
        XCTAssertEqual(schedule.slots.map(\.minutes), [300, 900])
        schedule.prune(keeping: [])
        XCTAssertNil(schedule.slots[1].wallpaperID)
    }
}
