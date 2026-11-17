import AppKit
import SwiftUI
import WallVueCore

enum Theme {
    /// The near-black, neutral canvas: wallpapers supply the colour.
    static let canvas = Color(red: 0.066, green: 0.07, blue: 0.086)
    static let cardRadius: CGFloat = 12
    static let contentInset: CGFloat = 40
    /// Space the floating top bar and player bar take, so content clears them.
    static let topBarHeight: CGFloat = 64
    static let playerBarClearance: CGFloat = 96
}

extension View {
    /// Liquid Glass on macOS 26 and later, a standard blur material before.
    /// Used for controls that float above content — never for content itself.
    @ViewBuilder
    func glass<S: Shape>(_ shape: S) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
        }
    }
}

/// Capsule button: glass by default, filled with the accent colour when
/// `prominent`.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var large = false

    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font((large ? Font.body : Font.callout).weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, large ? 18 : 14)
            .padding(.vertical, large ? 10 : 7)
            .contentShape(Capsule())
        Group {
            if prominent {
                label.background(Capsule().fill(.tint))
            } else {
                label.glass(Capsule())
            }
        }
        .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Round icon-only button on glass.
struct CircleButtonStyle: ButtonStyle {
    var diameter: CGFloat = 34

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: diameter * 0.42, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
            .glass(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Selectable filter chip.
struct Chip: View {
    let title: String
    var symbol: String?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.85))
            .background {
                if isSelected {
                    Capsule().fill(.tint)
                } else {
                    Capsule().fill(.white.opacity(0.06))
                    Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Page title + one-line description, as on Stills / Library / Playlists.
struct PageHeader<Trailing: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 34, weight: .bold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 16)
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// Loads a thumbnail from disk once and keeps it in memory.
struct ThumbnailImage: View {
    let url: URL?
    @State private var image: NSImage?

    var body: some View {
        // The image is an overlay so that an aspect-fill picture can never
        // make this view larger than the space it was offered.
        Rectangle()
            .fill(.white.opacity(0.05))
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                }
            }
            .clipped()
            .task(id: url) { image = ThumbnailCache.shared.image(for: url) }
    }
}

@MainActor
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSURL, NSImage>()

    func image(for url: URL?) -> NSImage? {
        guard let url else { return nil }
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    func clear() { cache.removeAllObjects() }
}

/// A wallpaper tile for grids and rows.
struct WallpaperCard: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    /// Second line under the title: category on browse pages, details in Library.
    var subtitle: String?
    var showsOnDiskBadge = false

    @State private var isHovering = false
    @State private var isRenaming = false
    @State private var draftTitle = ""

    private var isLive: Bool { model.engine.isShowing(wallpaper) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            thumbnail
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(wallpaper.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text(subtitle ?? wallpaper.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button {
                    model.library.toggleFavorite(wallpaper)
                } label: {
                    Image(systemName: wallpaper.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(wallpaper.isFavorite ? Color.pink : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites")
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.open(wallpaper) }
        .contextMenu { menu }
        .alert("Rename Wallpaper", isPresented: $isRenaming) {
            TextField("Name", text: $draftTitle)
            Button("Rename") { model.library.rename(wallpaper, to: draftTitle) }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(wallpaper.title), \(wallpaper.category)\(isLive ? ", playing" : "")")
        .accessibilityAddTraits(.isButton)
    }

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        return Color.clear
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .overlay { ThumbnailImage(url: wallpaper.thumbnailURL) }
            .overlay {
                if isHovering {
                    Image(systemName: wallpaper.kind == .video ? "play.fill" : "photo.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .glass(Circle())
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .overlay(alignment: .topLeading) {
                if isLive {
                    badge("Playing", symbol: "dot.radiowaves.left.and.right", filled: true)
                } else if showsOnDiskBadge, wallpaper.isOnDisk {
                    badge("On Your Mac", symbol: "checkmark.circle.fill", filled: false)
                }
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(isLive ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.08)), lineWidth: isLive ? 2 : 0.5)
            }
            .animation(.snappy(duration: 0.2), value: isHovering)
    }

    private func badge(_ text: String, symbol: String, filled: Bool) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(filled ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.black.opacity(0.55)), in: Capsule())
            .padding(8)
    }

    @ViewBuilder
    private var menu: some View {
        let displays = model.engine.displays
        Button("Set as Wallpaper") { model.engine.setWallpaper(wallpaper) }
        if displays.count > 1, wallpaper.kind == .video {
            Menu("Set on Display") {
                ForEach(displays) { display in
                    Button(display.name) { model.engine.setWallpaper(wallpaper, onDisplay: display.id) }
                }
            }
        }
        Button("View Wallpaper") { model.open(wallpaper) }
        Divider()
        Button(wallpaper.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            model.library.toggleFavorite(wallpaper)
        }
        Menu("Category") {
            ForEach(Wallpaper.categories, id: \.self) { category in
                Button {
                    model.library.setCategory(category, for: wallpaper)
                } label: {
                    if category == wallpaper.category {
                        Label(category, systemImage: "checkmark")
                    } else {
                        Text(category)
                    }
                }
            }
        }
        Button("Rename…") {
            draftTitle = wallpaper.title
            isRenaming = true
        }
        if wallpaper.kind == .video, LoopPlan.canLoop(duration: wallpaper.duration) {
            Button("Make Seamless Loop…") { model.loopSource = wallpaper }
        }
        Button("Show in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting([wallpaper.fileURL])
        }
        Divider()
        Button("Remove from Library", role: .destructive) { model.remove(wallpaper) }
    }
}

/// The adaptive grid every browse page uses.
struct WallpaperGrid<Leading: View>: View {
    let wallpapers: [Wallpaper]
    var subtitle: (Wallpaper) -> String? = { _ in nil }
    var showsOnDiskBadge = false
    @ViewBuilder var leading: Leading

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 420), spacing: 20)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
            ForEach(wallpapers) { wallpaper in
                WallpaperCard(wallpaper: wallpaper, subtitle: subtitle(wallpaper), showsOnDiskBadge: showsOnDiskBadge)
            }
            leading
        }
    }
}

extension WallpaperGrid where Leading == EmptyView {
    init(wallpapers: [Wallpaper], subtitle: @escaping (Wallpaper) -> String? = { _ in nil }, showsOnDiskBadge: Bool = false) {
        self.init(wallpapers: wallpapers, subtitle: subtitle, showsOnDiskBadge: showsOnDiskBadge) { EmptyView() }
    }
}

/// Standard scrolling page: clears the floating top bar and player bar.
struct PageScroll<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                content
            }
            .padding(.horizontal, Theme.contentInset)
            .padding(.top, Theme.topBarHeight + 20)
            .padding(.bottom, Theme.playerBarClearance)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
