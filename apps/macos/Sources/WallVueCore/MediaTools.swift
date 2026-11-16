import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MediaError: LocalizedError {
    case notPlayable(String)
    case noVideoTrack(String)
    case imageWriteFailed
    case unreadableImage(String)

    public var errorDescription: String? {
        switch self {
        case .notPlayable(let name): return "“\(name)” can't be played on this Mac."
        case .noVideoTrack(let name): return "“\(name)” has no video track."
        case .imageWriteFailed: return "Couldn't save a preview image."
        case .unreadableImage(let name): return "“\(name)” isn't an image this Mac can read."
        }
    }
}

public struct MediaInfo: Sendable {
    public var width: Int
    public var height: Int
    public var duration: Double
    public var frameRate: Double
    public var hasAudio: Bool
}

/// Stateless helpers around AVFoundation: inspecting a file and pulling
/// frames out of it.
public enum MediaTools {
    public static func inspect(_ url: URL) async throws -> MediaInfo {
        let name = url.lastPathComponent
        let asset = AVURLAsset(url: url)
        guard try await asset.load(.isPlayable) else { throw MediaError.notPlayable(name) }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else {
            throw MediaError.noVideoTrack(name)
        }
        let duration = try await asset.load(.duration)
        let (size, transform, fps) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
        // Rotated clips (e.g. shot on a phone) report their unrotated size.
        let display = CGRect(origin: .zero, size: size).applying(transform)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        return MediaInfo(
            width: Int(abs(display.width).rounded()),
            height: Int(abs(display.height).rounded()),
            duration: duration.seconds.isFinite ? duration.seconds : 0,
            frameRate: Double(fps),
            hasAudio: !audioTracks.isEmpty
        )
    }

    /// Extracts the frame at `seconds`. `maxDimension` of 0 keeps full size.
    public static func frame(of url: URL, at seconds: Double, maxDimension: CGFloat) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        if maxDimension > 0 {
            generator.maximumSize = CGSize(width: maxDimension, height: maxDimension)
        }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        return try await generator.image(at: time).image
    }

    public static func writeJPEG(_ image: CGImage, to url: URL, quality: Double) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, UTType.jpeg.identifier as CFString, 1, nil
        ) else { throw MediaError.imageWriteFailed }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination) else { throw MediaError.imageWriteFailed }
    }

    // MARK: Still images

    public static func imageSize(of url: URL) throws -> (width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw MediaError.unreadableImage(url.lastPathComponent) }
        return (width, height)
    }

    public static func imageThumbnail(of url: URL, maxDimension: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
