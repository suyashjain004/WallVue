import AppKit
import AVFoundation
import SwiftUI
import WallVueCore

/// A muted, looping preview of a video file that fills its bounds.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.load(url)
        return view
    }

    func updateNSView(_ view: PlayerView, context: Context) {
        if view.url != url { view.load(url) }
    }

    static func dismantleNSView(_ view: PlayerView, coordinator: ()) {
        view.tearDown()
    }

    final class PlayerView: NSView {
        private(set) var url: URL?
        private var player: AVQueuePlayer?
        private var looper: AVPlayerLooper?
        private let playerLayer = AVPlayerLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer = CALayer()
            layer?.backgroundColor = NSColor.black.cgColor
            playerLayer.videoGravity = .resizeAspectFill
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            layer?.addSublayer(playerLayer)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            playerLayer.frame = bounds
            CATransaction.commit()
        }

        func load(_ url: URL) {
            tearDown()
            self.url = url
            let queue = AVQueuePlayer()
            queue.isMuted = true
            queue.preventsDisplaySleepDuringVideoPlayback = false
            looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
            playerLayer.player = queue
            player = queue
            queue.play()
        }

        func tearDown() {
            player?.pause()
            looper?.disableLooping()
            looper = nil
            player?.removeAllItems()
            playerLayer.player = nil
            player = nil
        }
    }
}

/// Full-window view of one wallpaper: the video itself is the page.
struct DetailView: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    @State private var showsMoreLikeThis = false
    @State private var confirmsRemoval = false

    private var isLive: Bool { model.engine.isShowing(wallpaper) }

    var body: some View {
        ZStack {
            backdrop
                .ignoresSafeArea()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.25),
                    .init(color: .clear, location: 0.5),
                    .init(color: .black.opacity(0.8), location: 1),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .allowsHitTesting(false)

            VStack(alignment: .leading) {
                Button {
                    model.detailID = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)
                .padding(.top, 58)

                Spacer()

                HStack(alignment: .bottom) {
                    info
                    Spacer()
                    Button {
                        showsMoreLikeThis = true
                    } label: {
                        Label("More like this", systemImage: "chevron.up")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(PillButtonStyle(large: true))
                    .disabled(model.library.similar(to: wallpaper).isEmpty)
                }
            }
            .padding(.horizontal, Theme.contentInset)
            .padding(.bottom, 36)

            if showsMoreLikeThis {
                MoreLikeThisView(source: wallpaper) { showsMoreLikeThis = false }
                    .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: showsMoreLikeThis)
        .confirmationDialog("Remove “\(wallpaper.title)” from your library?", isPresented: $confirmsRemoval) {
            Button("Remove", role: .destructive) { model.remove(wallpaper) }
        } message: {
            Text("The file WallVue copied is deleted. Your original file is not touched.")
        }
    }

    @ViewBuilder
    private var backdrop: some View {
        if wallpaper.kind == .video, wallpaper.isOnDisk {
            LoopingVideoView(url: wallpaper.fileURL)
        } else {
            ThumbnailImage(url: wallpaper.kind == .still ? wallpaper.fileURL : wallpaper.thumbnailURL)
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(wallpaper.category.uppercased())
                .font(.caption.weight(.semibold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.75))
            Text(wallpaper.title)
                .font(.system(size: 40, weight: .bold))
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(wallpaper.detailLabel)
                if wallpaper.is4K { QualityBadge(text: "4K") }
                if wallpaper.hasAudio { Image(systemName: "speaker.wave.2.fill").help("Has sound") }
            }
            .font(.callout)
            .foregroundStyle(.white.opacity(0.8))

            HStack(spacing: 10) {
                setButton
                Button {
                    model.library.toggleFavorite(wallpaper)
                } label: {
                    Image(systemName: wallpaper.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(wallpaper.isFavorite ? Color.pink : Color.white)
                }
                .buttonStyle(CircleButtonStyle(diameter: 40))
                .help(wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites")
                .accessibilityLabel(wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites")

                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([wallpaper.fileURL])
                } label: {
                    Image(systemName: "folder")
                }
                .buttonStyle(CircleButtonStyle(diameter: 40))
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")

                if wallpaper.kind == .video, LoopPlan.canLoop(duration: wallpaper.duration) {
                    Button {
                        model.loopSource = wallpaper
                    } label: {
                        Image(systemName: "repeat")
                    }
                    .buttonStyle(CircleButtonStyle(diameter: 40))
                    .help("Make a seamless loop")
                    .accessibilityLabel("Make a seamless loop")
                }

                ShareLink(item: wallpaper.fileURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PillButtonStyle(large: true))

                Button {
                    confirmsRemoval = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(CircleButtonStyle(diameter: 40))
                .help("Remove from Library")
                .accessibilityLabel("Remove from Library")
            }
            .padding(.top, 6)

            Text(wallpaper.kind == .video
                 ? "Plays on the desktop of every display. Lock Screen and screen saver follow your Lock Screen settings."
                 : "Applies to the desktop and Lock Screen of every display.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    @ViewBuilder
    private var setButton: some View {
        let displays = model.engine.displays
        if displays.count > 1, wallpaper.kind == .video {
            Menu {
                Button("All Displays") { model.engine.setWallpaper(wallpaper) }
                Divider()
                ForEach(displays) { display in
                    Button(display.name) { model.engine.setWallpaper(wallpaper, onDisplay: display.id) }
                }
            } label: {
                Label(isLive ? "On Your Mac" : "Set Wallpaper", systemImage: isLive ? "checkmark" : "play.fill")
            } primaryAction: {
                model.engine.setWallpaper(wallpaper)
            }
            .menuStyle(.button)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.large)
            .fixedSize()
        } else {
            Button {
                model.engine.setWallpaper(wallpaper)
            } label: {
                Label(isLive ? "On Your Mac" : "Set Wallpaper", systemImage: isLive ? "checkmark" : "play.fill")
            }
            .buttonStyle(PillButtonStyle(prominent: true, large: true))
            .disabled(isLive)
        }
    }
}

/// Similar wallpapers as a vertical depth carousel: the focused card sits
/// forward, neighbours tilt away. Scroll or use the arrow keys; Return opens.
struct MoreLikeThisView: View {
    @Environment(AppModel.self) private var model
    let source: Wallpaper
    let onClose: () -> Void

    @State private var index = 0
    @State private var scrollAccumulator: CGFloat = 0
    @State private var scrollMonitor: Any?
    @FocusState private var isFocused: Bool

    private var items: [Wallpaper] { model.library.similar(to: source) }

    var body: some View {
        let items = items
        let focused = items.isEmpty ? nil : items[min(index, items.count - 1)]

        ZStack {
            Rectangle()
                .fill(.black.opacity(0.55))
                .background(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("MORE LIKE THIS   \(min(index + 1, items.count)) / \(items.count)")
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(focused?.title ?? "")
                        .font(.system(size: 30, weight: .bold))
                        .lineLimit(3)
                    Text(focused?.category ?? "")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Button {
                        if let focused { model.open(focused) }
                    } label: {
                        Label("Open", systemImage: "play.fill")
                    }
                    .buttonStyle(PillButtonStyle(large: true))
                    .padding(.top, 6)
                    Text("Scroll to browse · ↩ open · esc close")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 260, alignment: .leading)

                carousel(items)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(alignment: .trailing, spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                        Button {
                            index = offset
                        } label: {
                            Text(item.title)
                                .font(.callout.weight(offset == index ? .bold : .regular))
                                .foregroundStyle(offset == index ? Color.white : Color.white.opacity(0.45))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 240, alignment: .trailing)
            }
            .padding(.horizontal, Theme.contentInset)

            VStack {
                HStack {
                    Button(action: onClose) { Image(systemName: "xmark") }
                        .buttonStyle(CircleButtonStyle())
                        .keyboardShortcut(.cancelAction)
                        .accessibilityLabel("Close")
                    Spacer()
                }
                Spacer()
            }
            .padding(.top, 58)
            .padding(.leading, Theme.contentInset)
        }
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear {
            isFocused = true
            // The overlay owns the scroll wheel while it is open.
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                handleScroll(event.scrollingDeltaY)
                return nil
            }
        }
        .onDisappear {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
        }
        .onKeyPress(.upArrow) { move(-1, count: items.count); return .handled }
        .onKeyPress(.downArrow) { move(1, count: items.count); return .handled }
        .onKeyPress(.return) {
            if let focused { model.open(focused) }
            return .handled
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: index)
    }

    private func carousel(_ items: [Wallpaper]) -> some View {
        GeometryReader { proxy in
            let cardWidth = min(proxy.size.width * 0.78, 620)
            let cardHeight = cardWidth * 9 / 16
            ZStack {
                ForEach(Array(items.enumerated()), id: \.element.id) { offset, item in
                    let distance = offset - index
                    if abs(distance) <= 2 {
                        ThumbnailImage(url: item.thumbnailURL)
                            .frame(width: cardWidth, height: cardHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
                            .scaleEffect(distance == 0 ? 1 : 0.82)
                            .rotation3DEffect(.degrees(Double(distance) * -38), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                            .offset(y: CGFloat(distance) * cardHeight * 0.86)
                            .opacity(distance == 0 ? 1 : 0.55)
                            .zIndex(Double(-abs(distance)))
                            .onTapGesture {
                                if distance == 0 { model.open(item) } else { index = offset }
                            }
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
        }
    }

    private func handleScroll(_ delta: CGFloat) {
        scrollAccumulator += delta
        guard abs(scrollAccumulator) > 28 else { return }
        move(scrollAccumulator > 0 ? -1 : 1, count: items.count)
        scrollAccumulator = 0
    }

    private func move(_ delta: Int, count: Int) {
        guard count > 0 else { return }
        index = min(max(index + delta, 0), count - 1)
    }
}
