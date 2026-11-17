import XCTest
@testable import WallVueCore

final class CallRuleTests: XCTestCase {
    func testCameraPausesByDefaultAndMicrophoneAndScreenAreOptIn() {
        var env = PlaybackEnvironment()
        env.cameraInUse = true
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: PlaybackRules()), .pause(.call))

        env = PlaybackEnvironment()
        env.microphoneInUse = true
        env.screenShared = true
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: PlaybackRules()), .play)

        var rules = PlaybackRules()
        rules.pauseForMicrophone = true
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: rules), .pause(.call))

        rules = PlaybackRules()
        rules.pauseWhenScreenShared = true
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: rules), .pause(.screenShared))
    }

    func testCallRuleCanBeTurnedOffAndUserPauseStillWins() {
        var env = PlaybackEnvironment()
        env.cameraInUse = true
        var rules = PlaybackRules()
        rules.pauseForCamera = false
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: rules), .play)

        env.userPaused = true
        XCTAssertEqual(PlaybackPolicy.decide(env, rules: PlaybackRules()), .pause(.user))
    }
}

final class LoopPlanTests: XCTestCase {
    func testSuggestedPlanUsesWholeClipWithOneSecondBlend() {
        let plan = LoopPlan.suggested(forDuration: 12)
        XCTAssertEqual(plan, LoopPlan(start: 0, end: 12, fade: 1))
        XCTAssertEqual(plan.outputDuration, 11, accuracy: 0.0001)
        XCTAssertEqual(plan.fadeStartInOutput, 10, accuracy: 0.0001)
    }

    func testBlendIsLimitedToAThirdOfTheStretch() {
        let plan = LoopPlan(start: 0, end: 3, fade: 4).clamped(toDuration: 3)
        XCTAssertEqual(plan.fade, 1, accuracy: 0.0001)
        XCTAssertEqual(plan.outputDuration, 2, accuracy: 0.0001)
        // The plain part before the blend is never empty.
        XCTAssertGreaterThan(plan.fadeStartInOutput, 0)
    }

    func testOutOfRangeAndReversedEndsAreRepaired() {
        let plan = LoopPlan(start: 9, end: -4, fade: -1).clamped(toDuration: 10)
        XCTAssertEqual(plan.start, 0, accuracy: 0.0001)
        XCTAssertEqual(plan.end, 9, accuracy: 0.0001)
        XCTAssertEqual(plan.fade, 0)
    }

    func testTooCloseEndsAreWidenedToTheMinimum() {
        let nearEnd = LoopPlan(start: 9.5, end: 9.8, fade: 0.5).clamped(toDuration: 10)
        XCTAssertEqual(nearEnd.end, 10, accuracy: 0.0001)
        XCTAssertEqual(nearEnd.span, LoopPlan.minimumSpan, accuracy: 0.0001)

        let nearStart = LoopPlan(start: 1, end: 1.2, fade: 0.5).clamped(toDuration: 10)
        XCTAssertEqual(nearStart.start, 1, accuracy: 0.0001)
        XCTAssertEqual(nearStart.span, LoopPlan.minimumSpan, accuracy: 0.0001)
    }

    func testVeryShortClipsCannotLoop() {
        XCTAssertFalse(LoopPlan.canLoop(duration: 1.5))
        XCTAssertFalse(LoopPlan.canLoop(duration: .nan))
        XCTAssertTrue(LoopPlan.canLoop(duration: 2))
    }

    /// Runs the real export. Needs a video file, so it only runs when
    /// `WALLVUE_SAMPLE_VIDEO` points at one (Scripts/dev.sh sets it when a
    /// sample clip is present).
    func testMakesAPlayableLoopFromARealVideo() async throws {
        guard let path = ProcessInfo.processInfo.environment["WALLVUE_SAMPLE_VIDEO"],
              FileManager.default.fileExists(atPath: path)
        else { throw XCTSkip("Set WALLVUE_SAMPLE_VIDEO to a video file to run this test.") }

        let source = URL(fileURLWithPath: path)
        let original = try await MediaTools.inspect(source)
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("wallvue-loop-test-\(UUID().uuidString).mov")
        defer { try? FileManager.default.removeItem(at: output) }

        let requested = LoopPlan(start: 0.5, end: original.duration, fade: 1)
        let used = try await LoopMaker.makeLoop(from: source, to: output, plan: requested)
        let loop = try await MediaTools.inspect(output)

        XCTAssertEqual(loop.duration, used.outputDuration, accuracy: 0.15)
        XCTAssertEqual(loop.width, original.width)
        XCTAssertEqual(loop.height, original.height)
        // The join: the loop's last frame must be decodable.
        _ = try await MediaTools.frame(of: output, at: max(0, loop.duration - 0.1), maxDimension: 320)
    }
}

final class UpdateCheckerTests: XCTestCase {
    func testVersionParsing() {
        XCTAssertEqual(AppVersion("1.4.2")?.parts, [1, 4, 2])
        XCTAssertEqual(AppVersion("v0.10")?.parts, [0, 10])
        XCTAssertEqual(AppVersion("2")?.description, "2")
        XCTAssertNil(AppVersion("wallpapers-1"))
        XCTAssertNil(AppVersion("1.2-beta"))
        XCTAssertNil(AppVersion("1..2"))
        XCTAssertNil(AppVersion(""))
    }

    func testVersionOrdering() throws {
        let older = try XCTUnwrap(AppVersion("0.9.12"))
        let newer = try XCTUnwrap(AppVersion("0.10.0"))
        XCTAssertLessThan(older, newer)
        XCTAssertEqual(AppVersion("1.4"), AppVersion("1.4.0"))
        XCTAssertEqual(AppVersion("1.4")?.hashValue, AppVersion("1.4.0")?.hashValue)
        XCTAssertGreaterThan(try XCTUnwrap(AppVersion("1.4.0.1")), try XCTUnwrap(AppVersion("1.4")))
    }

    func testNewestReleaseSkipsWallpaperReleasesDraftsAndPrereleases() throws {
        let json = """
        [
          {"tag_name": "wallpapers-2", "html_url": "https://github.com/o/r/releases/tag/wallpapers-2", "draft": false, "prerelease": false},
          {"tag_name": "v0.9.0", "html_url": "https://github.com/o/r/releases/tag/v0.9.0", "draft": false, "prerelease": false},
          {"tag_name": "v0.10.1", "html_url": "https://github.com/o/r/releases/tag/v0.10.1", "draft": false, "prerelease": false},
          {"tag_name": "v0.11.0", "html_url": "https://github.com/o/r/releases/tag/v0.11.0", "draft": false, "prerelease": true},
          {"tag_name": "v1.0.0", "html_url": "https://github.com/o/r/releases/tag/v1.0.0", "draft": true, "prerelease": false}
        ]
        """
        let newest = try XCTUnwrap(UpdateChecker.newestRelease(inReleasesJSON: Data(json.utf8)))
        XCTAssertEqual(newest.version.description, "0.10.1")
        XCTAssertEqual(newest.page.absoluteString, "https://github.com/o/r/releases/tag/v0.10.1")
    }

    func testNoAppReleaseMeansNoUpdate() {
        let onlyWallpapers = """
        [{"tag_name": "wallpapers-1", "html_url": "https://github.com/o/r/releases/tag/wallpapers-1", "draft": false, "prerelease": false}]
        """
        XCTAssertNil(UpdateChecker.newestRelease(inReleasesJSON: Data(onlyWallpapers.utf8)))
        XCTAssertNil(UpdateChecker.newestRelease(inReleasesJSON: Data("[]".utf8)))
        XCTAssertNil(UpdateChecker.newestRelease(inReleasesJSON: Data("not json".utf8)))
    }

    func testReleasesAddressComesFromTheRepositoryAddress() {
        let api = UpdateChecker.releasesAPI(forRepository: URL(string: "https://github.com/suyashjain004/WallVue")!)
        XCTAssertEqual(api?.absoluteString, "https://api.github.com/repos/suyashjain004/WallVue/releases?per_page=50")
        XCTAssertNil(UpdateChecker.releasesAPI(forRepository: URL(string: "https://example.com/a/b")!))
    }
}
