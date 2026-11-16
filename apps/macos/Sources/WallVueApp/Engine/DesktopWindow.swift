import AppKit
import AVFoundation
import CoreImage
import WallVueCore

extension NSScreen {
    /// A stable identifier for this physical display (survives reboots and
    /// re-plugging, unlike the numeric display ID).
    var displayKey: String {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid)
        else { return localizedName }
        return string as String
    }
}

/// One looping video: a queue player, its looper and the layer that shows it.
@MainActor
final class VideoSurface {
    let player = AVQueuePlayer()
    let layer: AVPlayerLayer
    private var looper: AVPlayerLooper?

    init(url: URL) {
        let item = AVPlayerItem(asset: AVURLAsset(url: url))
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        // A wallpaper must never keep the display awake.
        player.preventsDisplaySleepDuringVideoPlayback = false
        player.allowsExternalPlayback = false
        looper = AVPlayerLooper(player: player, templateItem: item)
        layer = AVPlayerLayer(player: player)
    }

    func tearDown() {
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        layer.player = nil
        layer.removeFromSuperlayer()
    }
}

/// A borderless window pinned just above the system wallpaper and below the
/// desktop icons, on one display, showing one video.
@MainActor
final class DesktopWindowController {
    let displayKey: String
    private(set) var wallpaperID: UUID?
    /// Called when the desktop on this display becomes covered or uncovered.
    var onVisibilityChange: (() -> Void)?

    private let window: NSWindow
    private let rootLayer = CALayer()
    /// Sits above the video: darkens it and blurs what is behind it, so
    /// desktop icons and widgets stay readable over a busy wallpaper.
    private let dimLayer = CALayer()
    private var appliedDim = -1.0
    private var appliedBlur = -1.0
    private var surface: VideoSurface?
    private var readyObservation: NSKeyValueObservation?
    private var occlusionObserver: NSObjectProtocol?

    /// False when other windows completely cover this display's desktop.
    var isDesktopVisible: Bool { window.occlusionState.contains(.visible) }

    init(screen: NSScreen) {
        displayKey = screen.displayKey
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.ignoresMouseEvents = true
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.animationBehavior = .none
        window.isExcludedFromWindowsMenu = true

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        rootLayer.backgroundColor = NSColor.black.cgColor
        view.layer = rootLayer
        view.wantsLayer = true
        view.layerUsesCoreImageFilters = true
        window.contentView = view

        dimLayer.frame = rootLayer.bounds
        dimLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        dimLayer.zPosition = 10
        dimLayer.backgroundColor = NSColor.clear.cgColor
        rootLayer.addSublayer(dimLayer)

        occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onVisibilityChange?() }
        }
    }

    func update(screen: NSScreen) {
        if window.frame != screen.frame {
            window.setFrame(screen.frame, display: true)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        rootLayer.contentsScale = screen.backingScaleFactor
        surface?.layer.frame = rootLayer.bounds
        dimLayer.frame = rootLayer.bounds
        CATransaction.commit()
    }

    /// Switches to `url`, cross-fading from whatever was showing. No-op when
    /// the same wallpaper is already up.
    func show(wallpaperID id: UUID, url: URL) {
        if wallpaperID == id, surface != nil { return }
        wallpaperID = id

        let previous = surface
        let next = VideoSurface(url: url)
        next.layer.frame = rootLayer.bounds
        next.layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        next.layer.opacity = 0
        rootLayer.addSublayer(next.layer)
        surface = next

        // Fade in only once the first frame is decoded, so there is never a
        // black flash between wallpapers.
        readyObservation = next.layer.observe(\.isReadyForDisplay, options: [.initial, .new]) { [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            Task { @MainActor in
                guard let self, self.surface === next else { return }
                self.readyObservation = nil
                CATransaction.begin()
                CATransaction.setAnimationDuration(0.6)
                CATransaction.setCompletionBlock {
                    Task { @MainActor in previous?.tearDown() }
                }
                next.layer.opacity = 1
                CATransaction.commit()
            }
        }

        window.orderFront(nil)
    }

    func apply(
        playing: Bool, rate: Float, muted: Bool, volume: Float,
        scaling: ScalingMode, dim: Double, blur: Double
    ) {
        if dim != appliedDim || blur != appliedBlur {
            appliedDim = dim
            appliedBlur = blur
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            dimLayer.backgroundColor = NSColor.black.withAlphaComponent(dim).cgColor
            if blur > 0.01, let filter = CIFilter(name: "CIGaussianBlur") {
                filter.setValue(blur * 40, forKey: kCIInputRadiusKey)
                dimLayer.backgroundFilters = [filter]
            } else {
                dimLayer.backgroundFilters = []
            }
            CATransaction.commit()
        }
        guard let surface else { return }
        switch scaling {
        case .fill: surface.layer.videoGravity = .resizeAspectFill
        case .fit: surface.layer.videoGravity = .resizeAspect
        case .stretch: surface.layer.videoGravity = .resize
        }
        surface.player.isMuted = muted
        surface.player.volume = volume
        if playing {
            if surface.player.rate != rate { surface.player.rate = rate }
        } else if surface.player.rate != 0 {
            surface.player.pause()
        }
    }

    func close() {
        if let occlusionObserver { NotificationCenter.default.removeObserver(occlusionObserver) }
        occlusionObserver = nil
        readyObservation = nil
        surface?.tearDown()
        surface = nil
        wallpaperID = nil
        window.orderOut(nil)
        window.close()
    }
}
