import SwiftUI
import WallVueCore

// MARK: - Home

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @State private var heroIndex = 0

    /// Up to six featured wallpapers: favourites first, then the rest of
    /// the library, then the catalogue.
    private var featured: [BrowseItem] {
        let videos = model.library.videos
        let ordered = videos.filter(\.isFavorite) + videos.filter { !$0.isFavorite }
        let catalogue = model.notDownloaded.filter { $0.kind == .video }
        return Array((ordered.map(BrowseItem.local) + catalogue.map(BrowseItem.remote)).prefix(6))
    }

    var body: some View {
        let featured = featured
        if featured.isEmpty {
            EmptyLibraryView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    HeroBanner(items: featured, index: $heroIndex, eyebrow: nil)

                    VStack(alignment: .leading, spacing: 34) {
                        CatalogueRow(title: "Free to download", entries: Array(model.notDownloaded.filter { $0.kind == .video }.prefix(12)))
                        WallpaperRow(title: "Recently added", wallpapers: Array(LibrarySort.newest.sorted(model.library.videos).prefix(12)))
                        WallpaperRow(title: "Recently played", wallpapers: Array(model.engine.recents.prefix(12)))
                        WallpaperRow(title: "Favorites", wallpapers: Array(model.library.favorites.prefix(12)))
                    }
                    .padding(.horizontal, Theme.contentInset)
                }
                .padding(.bottom, Theme.playerBarClearance)
            }
            .task { await model.catalogue.refresh() }
        }
    }
}

struct EmptyLibraryView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ContentUnavailableView {
            Label("Bring your desktop to life", systemImage: "sparkles.tv")
        } description: {
            Text("Add a video and it becomes a live wallpaper on every display.\nDrop MP4 or MOV files anywhere in this window to start.")
        } actions: {
            Button {
                model.showUpload()
            } label: {
                Label("Upload Wallpaper", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(PillButtonStyle(prominent: true, large: true))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Full-width featured banner with a pager, used on Home and Explore.
struct HeroBanner: View {
    @Environment(AppModel.self) private var model
    let items: [BrowseItem]
    @Binding var index: Int
    let eyebrow: String?

    private var safeIndex: Int { min(max(index, 0), items.count - 1) }

    var body: some View {
        let item = items[safeIndex]

        ZStack(alignment: .bottomLeading) {
            ThumbnailImage(url: model.thumbnailURL(for: item))
                .id(item.id)
                .transition(.opacity)
                .frame(maxWidth: .infinity)
                .frame(height: 520)
                .clipped()
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.35), location: 0),
                            .init(color: .clear, location: 0.3),
                            .init(color: Theme.canvas.opacity(0.75), location: 0.8),
                            .init(color: Theme.canvas, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                }

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text((eyebrow ?? item.category).uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.2)
                        .foregroundStyle(.secondary)
                    Text(item.title)
                        .font(.system(size: 40, weight: .bold))
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(item.detailLabel)
                        if item.is4K { QualityBadge(text: "4K") }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Button {
                            model.open(item)
                        } label: {
                            Label("View Wallpaper", systemImage: "play.fill")
                        }
                        .buttonStyle(PillButtonStyle(prominent: true, large: true))

                        switch item {
                        case .local(let wallpaper):
                            Button {
                                model.library.toggleFavorite(wallpaper)
                            } label: {
                                Label(wallpaper.isFavorite ? "Favorited" : "Favorite", systemImage: wallpaper.isFavorite ? "heart.fill" : "heart")
                            }
                            .buttonStyle(PillButtonStyle(large: true))
                        case .remote(let entry):
                            Button {
                                model.get(entry, andSet: true)
                            } label: {
                                Label(model.isGetting(entry) ? "Downloading…" : "Download & Set", systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(PillButtonStyle(large: true))
                            .disabled(model.isGetting(entry))
                        }
                    }
                    .padding(.top, 6)
                }
                Spacer()
                if items.count > 1 { pager }
            }
            .padding(.horizontal, Theme.contentInset)
            .padding(.bottom, 28)
        }
        .animation(.easeInOut(duration: 0.35), value: safeIndex)
    }

    private var pager: some View {
        HStack(spacing: 12) {
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous")
            HStack(spacing: 5) {
                ForEach(items.indices, id: \.self) { i in
                    Capsule()
                        .fill(.white.opacity(i == safeIndex ? 1 : 0.35))
                        .frame(width: i == safeIndex ? 22 : 6, height: 4)
                }
            }
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("Next")
        }
        .buttonStyle(.plain)
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glass(Capsule())
    }

    private func step(_ delta: Int) {
        let count = items.count
        index = ((safeIndex + delta) % count + count) % count
    }
}

struct QualityBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary, lineWidth: 1))
    }
}

/// A titled, horizontally scrolling row of cards. Hidden when empty.
struct WallpaperRow: View {
    let title: String
    let wallpapers: [Wallpaper]

    var body: some View {
        if !wallpapers.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title2.weight(.bold))
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 20) {
                        ForEach(wallpapers) { wallpaper in
                            WallpaperCard(wallpaper: wallpaper)
                                .frame(width: 300)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }
}

// MARK: - Explore

struct ExploreView: View {
    @Environment(AppModel.self) private var model
    @State private var heroIndex = 0
    @State private var category: String?
    @State private var only4K = false
    @State private var onlyUltrawide = false
    @State private var sort: LibrarySort = .newest

    /// Everything there is to browse: the library's videos, then the
    /// catalogue's videos that aren't downloaded yet.
    private var everything: [BrowseItem] {
        model.library.videos.map(BrowseItem.local)
            + model.notDownloaded.filter { $0.kind == .video }.map(BrowseItem.remote)
    }

    private var results: [BrowseItem] {
        var items = everything
        if let category { items = items.filter { $0.category == category } }
        if only4K { items = items.filter(\.is4K) }
        if onlyUltrawide { items = items.filter(\.isUltrawide) }
        return BrowseItem.sorted(items, by: sort)
    }

    var body: some View {
        let newest = Array(BrowseItem.sorted(everything, by: .newest).prefix(6))
        if newest.isEmpty {
            EmptyLibraryView()
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 30) {
                    HeroBanner(items: newest, index: $heroIndex, eyebrow: nil)

                    VStack(alignment: .leading, spacing: 18) {
                        HStack {
                            Text("All Wallpapers")
                                .font(.title.weight(.bold))
                            Spacer()
                            Chip(title: "4K", symbol: "4k.tv", isSelected: only4K) { only4K.toggle() }
                            Chip(title: "Ultrawide", symbol: "arrow.left.and.right", isSelected: onlyUltrawide) { onlyUltrawide.toggle() }
                            Menu {
                                Picker("Sort By", selection: $sort) {
                                    ForEach(LibrarySort.allCases) { option in
                                        Label(option.label, systemImage: option.symbol).tag(option)
                                    }
                                }
                                .pickerStyle(.inline)
                            } label: {
                                Label(sort.label, systemImage: "arrow.up.arrow.down")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                Chip(title: "All", isSelected: category == nil) { category = nil }
                                ForEach(Wallpaper.categories, id: \.self) { name in
                                    Chip(title: name, isSelected: category == name) { category = name }
                                }
                            }
                        }

                        let results = results
                        if results.isEmpty {
                            ContentUnavailableView(
                                "Nothing matches",
                                systemImage: "line.3.horizontal.decrease.circle",
                                description: Text("Try another category or turn a filter off.")
                            )
                            .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            BrowseGrid(items: results)
                        }
                    }
                    .padding(.horizontal, Theme.contentInset)
                }
                .padding(.bottom, Theme.playerBarClearance)
            }
            .task { await model.catalogue.refresh() }
        }
    }
}

// MARK: - Stills

struct StillsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        PageScroll {
            PageHeader(title: "Stills", subtitle: "Still images for your desktop. Light on battery.")
            let stills = model.library.stills
            if stills.isEmpty {
                ContentUnavailableView {
                    Label("No stills yet", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Add JPEG, PNG or HEIC images and set them like any other wallpaper.")
                } actions: {
                    Button("Add Images…") { model.isImporterPresented = true }
                        .buttonStyle(PillButtonStyle(prominent: true))
                }
                .frame(maxWidth: .infinity, minHeight: 320)
            } else {
                WallpaperGrid(wallpapers: stills, subtitle: { $0.sizeLabel })
            }
        }
    }
}

// MARK: - Library

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all, favorites, downloaded, onYourMac, myUploads

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .favorites: return "Favorites"
        case .downloaded: return "Downloaded"
        case .onYourMac: return "On Your Mac"
        case .myUploads: return "My Uploads"
        }
    }

    var symbol: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorites: return "heart"
        case .downloaded: return "arrow.down.circle"
        case .onYourMac: return "desktopcomputer"
        case .myUploads: return "icloud.and.arrow.up"
        }
    }

    func apply(to items: [Wallpaper]) -> [Wallpaper] {
        switch self {
        case .all: return items
        case .favorites: return items.filter(\.isFavorite)
        case .downloaded: return items.filter { $0.origin == .catalogue }
        case .onYourMac: return items.filter(\.isOnDisk)
        case .myUploads: return items.filter { $0.origin == .imported }
        }
    }
}

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: LibraryFilter = .all

    var body: some View {
        PageScroll {
            PageHeader(title: "Library", subtitle: "Wallpapers you save live here") {
                Button {
                    model.showUpload()
                } label: {
                    Label("Add Your Own", systemImage: "plus")
                }
                .buttonStyle(PillButtonStyle())
            }

            HStack(spacing: 8) {
                ForEach(LibraryFilter.allCases) { option in
                    Chip(title: option.title, symbol: option.symbol, isSelected: filter == option) { filter = option }
                }
                Spacer()
                Button {
                    model.engine.shuffleNow()
                } label: {
                    Label("Shuffle", systemImage: "shuffle")
                }
                .buttonStyle(PillButtonStyle())
                .disabled(model.library.videos.isEmpty)
            }

            WallpaperGrid(
                wallpapers: filter.apply(to: model.library.wallpapers),
                subtitle: { "\($0.width)×\($0.height) · \($0.sizeLabel)" },
                showsOnDiskBadge: true
            ) {
                UploadTile()
            }
        }
    }
}

private struct UploadTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            model.showUpload()
        } label: {
            Color.clear
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    VStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.title3.weight(.semibold))
                            .frame(width: 44, height: 44)
                            .background(.white.opacity(0.08), in: Circle())
                        Text("Upload Wallpaper")
                            .font(.callout.weight(.semibold))
                    }
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [6, 5]))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}
