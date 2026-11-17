import AppKit
import SwiftUI
import WallVueCore

/// Something that can sit in a browse grid: a wallpaper already in the
/// library, or one in the catalogue that hasn't been downloaded yet.
enum BrowseItem: Identifiable, Hashable {
    case local(Wallpaper)
    case remote(CatalogueEntry)

    var id: String {
        switch self {
        case .local(let wallpaper): return wallpaper.id.uuidString
        case .remote(let entry): return "catalogue-\(entry.id)"
        }
    }

    var title: String {
        switch self {
        case .local(let wallpaper): return wallpaper.title
        case .remote(let entry): return entry.title
        }
    }

    var category: String {
        switch self {
        case .local(let wallpaper): return wallpaper.category
        case .remote(let entry): return entry.category
        }
    }

    var size: Int64 {
        switch self {
        case .local(let wallpaper): return wallpaper.fileSize
        case .remote(let entry): return entry.size
        }
    }

    var is4K: Bool {
        switch self {
        case .local(let wallpaper): return wallpaper.is4K
        case .remote(let entry): return entry.is4K
        }
    }

    var isUltrawide: Bool {
        switch self {
        case .local(let wallpaper): return wallpaper.isUltrawide
        case .remote(let entry): return entry.isUltrawide
        }
    }

    var detailLabel: String {
        switch self {
        case .local(let wallpaper): return wallpaper.detailLabel
        case .remote(let entry): return entry.detailLabel
        }
    }

    /// Library wallpapers keep their own order for "newest" and "most
    /// played"; catalogue ones follow, in the catalogue's order.
    static func sorted(_ items: [BrowseItem], by sort: LibrarySort) -> [BrowseItem] {
        switch sort {
        case .name:
            return items.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .largest:
            return items.sorted { $0.size > $1.size }
        case .newest, .mostPlayed:
            var locals: [Wallpaper] = []
            var remotes: [BrowseItem] = []
            for item in items {
                if case .local(let wallpaper) = item { locals.append(wallpaper) } else { remotes.append(item) }
            }
            return sort.sorted(locals).map(BrowseItem.local) + remotes
        }
    }
}

/// A catalogue wallpaper's tile. Looks like a library card, with a download
/// button where the favourite heart would be.
struct CatalogueCard: View {
    @Environment(AppModel.self) private var model
    let entry: CatalogueEntry
    @State private var isHovering = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay { ThumbnailImage(url: model.catalogue.thumbnailFile(for: entry)) }
                .overlay {
                    if isHovering {
                        Image(systemName: "play.fill")
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .glass(Circle())
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .clipShape(shape)
                .overlay { shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5) }
                .animation(.snappy(duration: 0.2), value: isHovering)

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    Text("\(entry.category) · \(Format.bytes(entry.size))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                DownloadButton(entry: entry)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .onTapGesture { model.open(entry) }
        .contextMenu {
            Button("Download and Set as Wallpaper") { model.get(entry, andSet: true) }
            Button("Download") { model.get(entry, andSet: false) }
            Button("View Wallpaper") { model.open(entry) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title), \(entry.category), not downloaded")
        .accessibilityAddTraits(.isButton)
    }
}

/// The small download control on a card: an arrow, or a ring while it loads.
struct DownloadButton: View {
    @Environment(AppModel.self) private var model
    let entry: CatalogueEntry

    var body: some View {
        if model.isGetting(entry) {
            ProgressView(value: model.catalogue.progress[entry.id] ?? 1)
                .progressViewStyle(.circular)
                .controlSize(.small)
                .help("Downloading")
                .accessibilityLabel("Downloading \(entry.title)")
        } else {
            Button {
                model.get(entry, andSet: false)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Download")
            .accessibilityLabel("Download \(entry.title)")
        }
    }
}

/// A grid that mixes library wallpapers and catalogue ones.
struct BrowseGrid: View {
    let items: [BrowseItem]
    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 420), spacing: 20)]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 26) {
            ForEach(items) { item in
                switch item {
                case .local(let wallpaper): WallpaperCard(wallpaper: wallpaper)
                case .remote(let entry): CatalogueCard(entry: entry)
                }
            }
        }
    }
}

/// A titled, horizontally scrolling row of catalogue cards. Hidden when empty.
struct CatalogueRow: View {
    let title: String
    let entries: [CatalogueEntry]

    var body: some View {
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title2.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(entries) { entry in
                            CatalogueCard(entry: entry)
                                .frame(width: 300)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}

/// Full-window page for a catalogue wallpaper that isn't on this Mac yet.
struct CatalogueDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    let entry: CatalogueEntry

    var body: some View {
        let busy = model.isGetting(entry)

        ZStack {
            ThumbnailImage(url: model.catalogue.thumbnailFile(for: entry))
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
                    model.catalogueDetailID = nil
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }
                .buttonStyle(PillButtonStyle())
                .keyboardShortcut(.cancelAction)
                .padding(.top, 58)

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    Text(entry.category.uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(entry.title)
                        .font(.system(size: 40, weight: .bold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(entry.detailLabel)
                        if entry.is4K { QualityBadge(text: "4K") }
                    }
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.8))

                    HStack(spacing: 10) {
                        if busy {
                            let fraction = model.catalogue.progress[entry.id] ?? 1
                            ProgressView(value: fraction)
                                .frame(width: 220)
                            Text(fraction < 1 ? "Downloading \(Int(fraction * 100))%" : "Adding to your Library")
                                .font(.callout.weight(.medium))
                                .monospacedDigit()
                        } else {
                            Button {
                                model.get(entry, andSet: true)
                            } label: {
                                Label("Download & Set", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(PillButtonStyle(prominent: true, large: true))

                            Button {
                                model.get(entry, andSet: false)
                            } label: {
                                Label("Download", systemImage: "arrow.down")
                            }
                            .buttonStyle(PillButtonStyle(large: true))

                            if let source = entry.source {
                                Button {
                                    openURL(source)
                                } label: {
                                    Label("Source", systemImage: "arrow.up.right")
                                }
                                .buttonStyle(PillButtonStyle(large: true))
                                .help("Where this wallpaper comes from")
                            }
                        }
                    }
                    .padding(.top, 6)
                    .frame(height: 44, alignment: .leading)

                    Text("By \(entry.credit) · Licence \(entry.license) · Free to download. It is saved to your Library and then plays like any other wallpaper.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.contentInset)
            .padding(.bottom, 36)
        }
    }
}
