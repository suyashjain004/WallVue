import AppKit
import SwiftUI
import WallVueCore

/// The panel behind the menu bar icon: what's playing, quick controls,
/// recent wallpapers and the app's own resource use.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.muted) private var muted = true
    @AppStorage(SettingsKey.shuffleEnabled) private var shuffleEnabled = false
    @AppStorage(SettingsKey.scheduleEnabled) private var scheduleEnabled = false

    var body: some View {
        let engine = model.engine
        let current = engine.current

        ZStack {
            ThumbnailImage(url: current?.thumbnailURL)
                .blur(radius: current == nil ? 0 : 2)
                .overlay(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(0.35), location: 0),
                            .init(color: .black.opacity(0.15), location: 0.35),
                            .init(color: Theme.canvas.opacity(0.92), location: 0.72),
                            .init(color: Theme.canvas, location: 1),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )

            VStack(spacing: 16) {
                header(engine)
                Spacer(minLength: 0)

                VStack(spacing: 6) {
                    Text((current?.category ?? AppInfo.name).uppercased())
                        .font(.caption.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(current?.title ?? "No wallpaper playing")
                        .font(.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Text(engine.statusLabel)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }

                transport(engine, current)
                recents(engine)
                footer(engine)
            }
            .padding(16)
        }
        .frame(width: 330, height: 500)
        .onAppear { model.stats.start() }
        .onDisappear { model.stats.stop() }
    }

    private func header(_ engine: WallpaperEngine) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(engine.isActive && engine.pauseReason == nil ? Color.green : Color.gray)
                .frame(width: 7, height: 7)
            Text("NOW PLAYING")
                .font(.caption.weight(.bold))
                .tracking(1.4)
            Spacer()
            Button { engine.shuffleNow() } label: { Image(systemName: "sparkles") }
                .buttonStyle(CircleButtonStyle(diameter: 30))
                .help("Surprise me")
                .accessibilityLabel("Surprise me")
            Button { showMainWindow() } label: { Image(systemName: "macwindow") }
                .buttonStyle(CircleButtonStyle(diameter: 30))
                .help("Open WallVue")
                .accessibilityLabel("Open WallVue")
            Menu {
                Button(engine.userPaused ? "Play" : "Pause") { engine.togglePause() }
                    .disabled(!engine.isActive)
                Button("Keyboard Shortcuts…") { showSettings(.shortcuts) }
                Divider()
                Button("Settings…") { showSettings(.general) }
                Button("Stop Wallpaper") { engine.stop() }
                    .disabled(!engine.isActive)
                Divider()
                Text("\(AppInfo.name) \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")")
                Button("Quit \(AppInfo.name)") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .glass(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
    }

    private func transport(_ engine: WallpaperEngine, _ current: Wallpaper?) -> some View {
        HStack(spacing: 12) {
            Button {
                if let current { model.library.toggleFavorite(current) }
            } label: {
                Image(systemName: current?.isFavorite == true ? "heart.fill" : "heart")
                    .foregroundStyle(current?.isFavorite == true ? Color.pink : Color.white)
            }
            .buttonStyle(CircleButtonStyle(diameter: 40))
            .disabled(current == nil)
            .accessibilityLabel("Favorite")

            Button { engine.step(by: -1) } label: { Image(systemName: "backward.fill") }
                .buttonStyle(CircleButtonStyle(diameter: 40))
                .accessibilityLabel("Previous")

            Button {
                if engine.isActive { engine.togglePause() } else { engine.step(by: 1) }
            } label: {
                Image(systemName: engine.isActive && !engine.userPaused ? "pause.fill" : "play.fill")
            }
            .buttonStyle(CircleButtonStyle(diameter: 56))
            .accessibilityLabel(engine.isActive && !engine.userPaused ? "Pause" : "Play")

            Button { engine.step(by: 1) } label: { Image(systemName: "forward.fill") }
                .buttonStyle(CircleButtonStyle(diameter: 40))
                .accessibilityLabel("Next")

            Button { muted.toggle() } label: {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
            }
            .buttonStyle(CircleButtonStyle(diameter: 40))
            .accessibilityLabel(muted ? "Turn sound on" : "Mute")
        }
    }

    @ViewBuilder
    private func recents(_ engine: WallpaperEngine) -> some View {
        let items = Array(engine.recents.prefix(5))
        if !items.isEmpty {
            HStack(spacing: 8) {
                ForEach(items) { wallpaper in
                    Button {
                        engine.setWallpaper(wallpaper)
                    } label: {
                        ThumbnailImage(url: wallpaper.thumbnailURL)
                            .frame(width: 52, height: 34)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(engine.isShowing(wallpaper) ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.15)), lineWidth: engine.isShowing(wallpaper) ? 2 : 0.5)
                            }
                    }
                    .buttonStyle(.plain)
                    .help(wallpaper.title)
                    .accessibilityLabel(wallpaper.title)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func footer(_ engine: WallpaperEngine) -> some View {
        HStack(spacing: 8) {
            Button {
                shuffleEnabled.toggle()
                if shuffleEnabled { scheduleEnabled = false }
            } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(shuffleEnabled ? Color.accentColor : Color.white)
            }
            .buttonStyle(CircleButtonStyle(diameter: 38))
            .help(shuffleEnabled ? "Shuffle is on" : "Shuffle")
            .accessibilityLabel("Shuffle")

            Button { showSettings(.displays) } label: { Image(systemName: "display.2") }
                .buttonStyle(CircleButtonStyle(diameter: 38))
                .help("Displays")
                .accessibilityLabel("Displays")

            Spacer()

            meter("\(model.stats.cpuPercent)", "CPU %")
            meter("\(model.stats.memoryMB)", "RAM MB")
            meter("\(model.stats.cacheMB)", "CACHE MB")
        }
    }

    private func meter(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value)
                .font(.callout.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(width: 46, height: 38)
        .glass(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
    }

    private func showMainWindow() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showSettings(_ pane: SettingsPane) {
        model.settingsPane = pane
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
