import SwiftUI
import UniformTypeIdentifiers
import WallVueCore

/// The main window: an edge-to-edge canvas with a floating tab bar on top
/// and a floating player bar at the bottom.
struct RootView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.hasCompletedOnboarding) private var hasCompletedOnboarding = false

    var body: some View {
        @Bindable var model = model

        ZStack {
            AmbientBackground()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if model.detailID == nil {
                VStack(spacing: 0) {
                    TopBar()
                    Spacer(minLength: 0)
                    NowPlayingPill()
                        .padding(.bottom, 18)
                }
                .transition(.opacity)
            }

            if model.isSearchShown {
                SearchPalette()
                    .transition(.opacity)
            }

            if model.library.importsInProgress > 0 {
                VStack {
                    ProgressToast(text: "Adding \(model.library.importsInProgress)…")
                        .padding(.top, Theme.topBarHeight + 8)
                    Spacer()
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 24)
                .transition(.opacity)
            }
        }
        .background(Theme.canvas)
        .ignoresSafeArea()
        .animation(.snappy(duration: 0.25), value: model.detailID)
        .animation(.snappy(duration: 0.2), value: model.isSearchShown)
        .animation(.snappy(duration: 0.2), value: model.library.importsInProgress)
        .fileImporter(
            isPresented: $model.isImporterPresented,
            allowedContentTypes: [.movie, .image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { model.importFiles(urls) }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls)
            return true
        }
        .alert(
            "Some files couldn't be added",
            isPresented: Binding(
                get: { model.library.lastError != nil },
                set: { if !$0 { model.library.lastError = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.library.lastError ?? "")
        }
        .sheet(isPresented: Binding(get: { !hasCompletedOnboarding }, set: { if !$0 { hasCompletedOnboarding = true } })) {
            OnboardingView { hasCompletedOnboarding = true }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let id = model.detailID, let wallpaper = model.library.wallpaper(id: id) {
            DetailView(wallpaper: wallpaper)
                .id(wallpaper.id)
                .transition(.opacity)
        } else if model.isUploadShown {
            UploadView()
        } else {
            switch model.tab {
            case .home: HomeView()
            case .explore: ExploreView()
            case .stills: StillsView()
            case .library: LibraryView()
            case .playlists: PlaylistsView()
            }
        }
    }
}

/// A soft wash of the playing wallpaper's colours behind the content.
private struct AmbientBackground: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.canvas
            if let current = model.engine.current {
                ThumbnailImage(url: current.thumbnailURL)
                    .blur(radius: 90)
                    .opacity(0.22)
                    .id(current.id)
                    .transition(.opacity)
            }
            LinearGradient(colors: [Theme.canvas.opacity(0.2), Theme.canvas.opacity(0.9)], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .animation(.easeInOut(duration: 0.8), value: model.engine.current?.id)
        .allowsHitTesting(false)
    }
}

/// Tab capsule in the centre, actions on the right. Floats over content.
private struct TopBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Namespace private var selection

    var body: some View {
        ZStack {
            tabs
            HStack(spacing: 10) {
                Spacer()
                Button {
                    model.showUpload()
                } label: {
                    Label("Upload Wallpaper", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(PillButtonStyle(prominent: true))
                .help("Add your own videos or images (⌘N)")

                HStack(spacing: 2) {
                    barIcon("magnifyingglass", help: "Search (⌘K)") { model.isSearchShown = true }
                    barIcon("questionmark.circle", help: "Help") {
                        model.settingsPane = .help
                        openWindow(id: "settings")
                    }
                    barIcon("gearshape", help: "Settings (⌘,)") { openWindow(id: "settings") }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .glass(Capsule())
            }
            .padding(.trailing, 20)
        }
        .frame(height: Theme.topBarHeight)
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                let isSelected = model.tab == tab && !model.isUploadShown
                Button {
                    withAnimation(.snappy(duration: 0.25)) { model.select(tab) }
                } label: {
                    Text(tab.title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.8))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.white.opacity(0.16))
                                    .matchedGeometryEffect(id: "tab", in: selection)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(4)
        .glass(Capsule())
    }

    private func barIcon(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

struct ProgressToast: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text).font(.callout.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glass(Capsule())
    }
}

/// The floating player bar shown on every tab.
struct NowPlayingPill: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.muted) private var muted = true
    @AppStorage(SettingsKey.playbackRate) private var playbackRate = 1.0
    @AppStorage(SettingsKey.shuffleEnabled) private var shuffleEnabled = false
    @AppStorage(SettingsKey.scheduleEnabled) private var scheduleEnabled = false

    private static let rates: [Double] = [0.5, 0.75, 1.0, 1.5, 2.0]

    var body: some View {
        let engine = model.engine
        let current = engine.current

        HStack(spacing: 14) {
            Button {
                if let current { model.open(current) }
            } label: {
                HStack(spacing: 10) {
                    ThumbnailImage(url: current?.thumbnailURL)
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(current?.title ?? "No wallpaper playing")
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(current == nil ? engine.targetLabel : "\(engine.statusLabel) · \(engine.targetLabel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(width: 280, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(current == nil)

            HStack(spacing: 4) {
                icon(current?.isFavorite == true ? "heart.fill" : "heart", help: "Favorite", tint: current?.isFavorite == true ? .pink : .white) {
                    if let current { model.library.toggleFavorite(current) }
                }
                .disabled(current == nil)

                icon("shuffle", help: shuffleEnabled ? "Shuffle is on" : "Shuffle", tint: shuffleEnabled ? .accentColor : .white) {
                    shuffleEnabled.toggle()
                    if shuffleEnabled {
                        scheduleEnabled = false
                        engine.shuffleNow()
                    }
                }

                Menu {
                    Picker("Speed", selection: $playbackRate) {
                        ForEach(Self.rates, id: \.self) { rate in
                            Text(Self.label(for: rate)).tag(rate)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Text(Self.label(for: playbackRate))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 30)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Playback speed")
            }

            Divider().frame(height: 26)

            Button {
                if engine.isActive {
                    engine.togglePause()
                } else {
                    engine.step(by: 1)
                }
            } label: {
                Image(systemName: engine.isActive && !engine.userPaused ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 38, height: 38)
                    .background(.white, in: Circle())
            }
            .buttonStyle(.plain)
            .help(engine.isActive && !engine.userPaused ? "Pause (⌥⌘P)" : "Play (⌥⌘P)")
            .accessibilityLabel(engine.isActive && !engine.userPaused ? "Pause" : "Play")

            icon(muted ? "speaker.slash.fill" : "speaker.wave.2.fill", help: muted ? "Turn sound on" : "Mute", tint: .white) {
                muted.toggle()
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .glass(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }

    private static func label(for rate: Double) -> String {
        rate == rate.rounded() ? "\(Int(rate))×" : "\(String(format: "%g", rate))×"
    }

    private func icon(_ symbol: String, help: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}
