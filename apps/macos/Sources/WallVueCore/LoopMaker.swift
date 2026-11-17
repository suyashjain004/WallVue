import AVFoundation
import CoreGraphics
import Foundation

/// The timing of a seamless loop cut from a longer clip.
///
/// The finished loop is the stretch `start + fade ... end` of the source.
/// Over its last `fade` seconds the stretch `start ... start + fade` is
/// blended in on top, so the final frame is exactly the frame the loop
/// begins on and the repeat can't be seen.
public struct LoopPlan: Equatable, Sendable {
    /// Seconds into the source where the loop's material starts.
    public var start: Double
    /// Seconds into the source where it ends.
    public var end: Double
    /// Length of the blend that hides the join.
    public var fade: Double

    /// Shortest stretch of source worth looping.
    public static let minimumSpan = 2.0
    public static let maximumFade = 4.0

    public init(start: Double, end: Double, fade: Double) {
        self.start = start
        self.end = end
        self.fade = fade
    }

    /// A sensible starting point: the whole clip with a one-second blend.
    public static func suggested(forDuration duration: Double) -> LoopPlan {
        LoopPlan(start: 0, end: duration, fade: 1).clamped(toDuration: duration)
    }

    public static func canLoop(duration: Double) -> Bool {
        duration.isFinite && duration >= minimumSpan
    }

    /// The same plan, forced into what a source of `duration` seconds can
    /// provide: inside the clip, at least `minimumSpan` long, and with a
    /// blend no longer than a third of the stretch.
    public func clamped(toDuration duration: Double) -> LoopPlan {
        let total = max(duration, 0)
        var low = min(max(start, 0), total)
        var high = min(max(end, 0), total)
        if high < low { swap(&low, &high) }
        if high - low < Self.minimumSpan {
            high = min(total, low + Self.minimumSpan)
            low = max(0, high - Self.minimumSpan)
        }
        let span = high - low
        let blend = min(max(fade, 0), Self.maximumFade, span / 3)
        return LoopPlan(start: low, end: high, fade: blend)
    }

    /// Length of source the loop is cut from.
    public var span: Double { end - start }
    /// Length of the finished loop.
    public var outputDuration: Double { max(span - fade, 0) }
    /// When, in the finished loop, the blend begins.
    public var fadeStartInOutput: Double { max(span - 2 * fade, 0) }
}

public enum LoopError: LocalizedError {
    case tooShort
    case exportUnavailable
    case exportFailed

    public var errorDescription: String? {
        switch self {
        case .tooShort: return "The video is too short to loop. It needs at least \(Int(LoopPlan.minimumSpan)) seconds."
        case .exportUnavailable: return "This Mac can't write the looped video."
        case .exportFailed: return "The looped video couldn't be saved."
        }
    }
}

/// Builds a seamlessly looping copy of a video.
public enum LoopMaker {
    /// Writes the loop described by `requested` to `output` (a `.mov`) and
    /// returns the plan that was actually used after clamping it to the clip.
    @discardableResult
    public static func makeLoop(from source: URL, to output: URL, plan requested: LoopPlan) async throws -> LoopPlan {
        let asset = AVURLAsset(url: source, options: [AVURLAssetPreferPreciseDurationAndTimingKey: true])
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaError.noVideoTrack(source.lastPathComponent)
        }
        let duration = try await asset.load(.duration).seconds
        guard LoopPlan.canLoop(duration: duration) else { throw LoopError.tooShort }
        let plan = requested.clamped(toDuration: duration)
        let (naturalSize, transform, fps) = try await videoTrack.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        let frameRate = fps > 0 ? Double(fps) : 30

        func time(_ seconds: Double) -> CMTime { CMTime(seconds: seconds, preferredTimescale: 600) }

        // Blends shorter than a frame are just a trim.
        let fades = plan.fade >= 1 / frameRate
        let body = CMTimeRange(start: time(plan.start + (fades ? plan.fade : 0)), end: time(plan.end))
        let fadeDuration = time(plan.fade)
        let join = CMTimeRange(start: CMTimeSubtract(body.duration, fadeDuration), duration: fadeDuration)
        let lead = CMTimeRange(start: time(plan.start), duration: fadeDuration)

        let composition = AVMutableComposition()
        guard let mainVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else { throw LoopError.exportUnavailable }
        try mainVideo.insertTimeRange(body, of: videoTrack, at: .zero)

        // Rotated clips carry a transform; render them upright at their
        // displayed size.
        let display = CGRect(origin: .zero, size: naturalSize).applying(transform)
        let upright = transform.concatenating(CGAffineTransform(translationX: -display.minX, y: -display.minY))

        let mainLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: mainVideo)
        mainLayer.setTransform(upright, at: .zero)
        var instructions: [AVMutableVideoCompositionInstruction] = []

        if fades {
            guard let leadVideo = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid
            ) else { throw LoopError.exportUnavailable }
            try leadVideo.insertTimeRange(lead, of: videoTrack, at: join.start)

            let leadLayer = AVMutableVideoCompositionLayerInstruction(assetTrack: leadVideo)
            leadLayer.setTransform(upright, at: .zero)
            leadLayer.setOpacityRamp(fromStartOpacity: 0, toEndOpacity: 1, timeRange: join)

            let plain = AVMutableVideoCompositionInstruction()
            plain.timeRange = CMTimeRange(start: .zero, duration: join.start)
            plain.layerInstructions = [mainLayer]

            let blended = AVMutableVideoCompositionInstruction()
            blended.timeRange = join
            // First in the list is drawn on top.
            blended.layerInstructions = [leadLayer, mainLayer]
            instructions = [plain, blended]
        } else {
            let plain = AVMutableVideoCompositionInstruction()
            plain.timeRange = CMTimeRange(start: .zero, duration: body.duration)
            plain.layerInstructions = [mainLayer]
            instructions = [plain]
        }

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = CGSize(
            width: max(2, abs(display.width).rounded()),
            height: max(2, abs(display.height).rounded())
        )
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate.rounded())))
        videoComposition.instructions = instructions

        // Sound follows the picture: the same cut, cross-faded at the join.
        // A clip whose sound can't be cut this way still gets its loop.
        var audioMix: AVMutableAudioMix?
        if let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first,
           let mainAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            if (try? mainAudio.insertTimeRange(body, of: audioTrack, at: .zero)) == nil {
                composition.removeTrack(mainAudio)
            } else if fades,
                      let leadAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
                if (try? leadAudio.insertTimeRange(lead, of: audioTrack, at: join.start)) == nil {
                    composition.removeTrack(leadAudio)
                } else {
                    let outgoing = AVMutableAudioMixInputParameters(track: mainAudio)
                    outgoing.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: join)
                    let incoming = AVMutableAudioMixInputParameters(track: leadAudio)
                    incoming.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: join)
                    let mix = AVMutableAudioMix()
                    mix.inputParameters = [outgoing, incoming]
                    audioMix = mix
                }
            }
        }

        let presets = [AVAssetExportPresetHEVCHighestQuality, AVAssetExportPresetHighestQuality]
        guard let session = presets.lazy.compactMap({ AVAssetExportSession(asset: composition, presetName: $0) }).first else {
            throw LoopError.exportUnavailable
        }
        session.videoComposition = videoComposition
        session.audioMix = audioMix
        try? FileManager.default.removeItem(at: output)

        if #available(macOS 15.0, *) {
            try await session.export(to: output, as: .mov)
        } else {
            session.outputURL = output
            session.outputFileType = .mov
            await session.export()
            if session.status != .completed { throw session.error ?? LoopError.exportFailed }
        }
        return plan
    }
}
