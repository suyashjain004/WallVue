import SwiftUI
import WallVueCore

// MARK: - Upload

struct UploadView: View {
    @Environment(AppModel.self) private var model
    @State private var isTargeted = false

    var body: some View {
        PageScroll {
            Button {
                model.isUploadShown = false
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .buttonStyle(PillButtonStyle())
            .keyboardShortcut(.cancelAction)

            PageHeader(title: "Upload Wallpaper", subtitle: "Add your own videos and images to your Library. Only you see them.")

            HStack(alignment: .top, spacing: 24) {
                dropZone
                steps
                    .frame(width: 340)
            }

            HStack(spacing: 8) {
                factChip("MP4, MOV or M4V · JPEG, PNG or HEIC", symbol: "film")
                factChip("Up to \(LibraryStore.maxImportBatch) at once", symbol: "square.stack")
                factChip("Stays on this Mac", symbol: "lock.shield")
            }

            let recent = model.recentlyImported.compactMap { model.library.wallpaper(id: $0) }
            if !recent.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Check the details")
                        .font(.title2.weight(.bold))
                    VStack(spacing: 0) {
                        ForEach(recent) { wallpaper in
                            ImportedRow(wallpaper: wallpaper)
                            Divider()
                        }
                    }
                }
                .padding(.top, 8)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.up")
                .font(.title2.weight(.semibold))
                .frame(width: 60, height: 60)
                .background(.white.opacity(0.08), in: Circle())
            Text("Drop your videos here")
                .font(.title2.weight(.bold))
            Text("Or images, to use as stills")
                .foregroundStyle(.secondary)
            Button {
                model.isImporterPresented = true
            } label: {
                Label("Choose Files", systemImage: "folder")
            }
            .buttonStyle(PillButtonStyle(prominent: true, large: true))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 360)
        .background(isTargeted ? AnyShapeStyle(TintShapeStyle().opacity(0.18)) : AnyShapeStyle(Color.white.opacity(0.03)), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(isTargeted ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.white.opacity(0.25)), style: StrokeStyle(lineWidth: 1.2, dash: [7, 6]))
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.importFiles(urls)
            return true
        } isTargeted: { isTargeted = $0 }
        .animation(.snappy(duration: 0.15), value: isTargeted)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add your own").font(.title3.weight(.bold))
                Text("Your files join your Library and play like any other wallpaper.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            step(1, "Choose files", "Drop them on the left or click Choose Files.")
            step(2, "Check the details", "WallVue suggests a title. Change it, pick a category, or make a seamless loop below.")
            step(3, "Set it", "Use Set Wallpaper here, or find it in Library.")
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.1), lineWidth: 0.5))
    }

    private func step(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.bold))
                .frame(width: 26, height: 26)
                .background(.white.opacity(0.1), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func factChip(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.white.opacity(0.05), in: Capsule())
    }
}

private struct ImportedRow: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    @State private var title = ""

    var body: some View {
        HStack(spacing: 14) {
            ThumbnailImage(url: wallpaper.thumbnailURL)
                .frame(width: 112, height: 63)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit { model.library.rename(wallpaper, to: title) }
                Text(wallpaper.detailLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Picker("Category", selection: Binding(
                get: { wallpaper.category },
                set: { model.library.setCategory($0, for: wallpaper) }
            )) {
                ForEach(Wallpaper.categories, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(width: 130)

            Spacer()

            if wallpaper.kind == .video, LoopPlan.canLoop(duration: wallpaper.duration) {
                Button {
                    model.loopSource = wallpaper
                } label: {
                    Label("Make Loop…", systemImage: "repeat")
                }
                .buttonStyle(PillButtonStyle())
                .help("Make a copy that repeats without a visible jump")
            }

            Button(model.engine.isShowing(wallpaper) ? "On Your Mac" : "Set Wallpaper") {
                model.library.rename(wallpaper, to: title)
                model.engine.setWallpaper(wallpaper)
            }
            .buttonStyle(PillButtonStyle(prominent: !model.engine.isShowing(wallpaper)))
            .disabled(model.engine.isShowing(wallpaper))
        }
        .padding(.vertical, 10)
        .onAppear { title = wallpaper.title }
        .onDisappear { model.library.rename(wallpaper, to: title) }
    }
}

// MARK: - Search

struct SearchPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @FocusState private var isFocused: Bool

    private var results: [Wallpaper] {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        return Array(model.library.wallpapers.filter {
            $0.title.localizedCaseInsensitiveContains(text) || $0.category.localizedCaseInsensitiveContains(text)
        }.prefix(8))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(.black.opacity(0.45))
                .ignoresSafeArea()
                .onTapGesture { model.isSearchShown = false }

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search wallpapers", text: $query)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .focused($isFocused)
                        .onSubmit { if let first = results.first { model.open(first) } }
                }
                .padding(.horizontal, 20)
                .frame(height: 58)
                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))

                VStack(spacing: 0) {
                    if query.trimmingCharacters(in: .whitespaces).isEmpty {
                        quickLink("Live Wallpapers", symbol: "play.rectangle.on.rectangle", shortcut: "⌘2", tab: .explore)
                        quickLink("Stills", symbol: "photo.on.rectangle", shortcut: "⌘3", tab: .stills)
                        quickLink("Library", symbol: "square.stack", shortcut: "⌘4", tab: .library)
                    } else if results.isEmpty {
                        Text("No wallpapers match “\(query)”")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(18)
                    } else {
                        ForEach(results) { wallpaper in
                            Button {
                                model.open(wallpaper)
                            } label: {
                                HStack(spacing: 12) {
                                    ThumbnailImage(url: wallpaper.thumbnailURL)
                                        .frame(width: 64, height: 36)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    Text(wallpaper.title).font(.body.weight(.semibold))
                                    Spacer()
                                    Text(wallpaper.category).foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 8)
                .glass(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .frame(width: 640)
            .padding(.top, 150)
        }
        .onAppear { isFocused = true }
        .onExitCommand { model.isSearchShown = false }
    }

    private func quickLink(_ title: String, symbol: String, shortcut: String, tab: AppTab) -> some View {
        Button {
            model.select(tab)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .frame(width: 28)
                Text(title).font(.body.weight(.semibold))
                Spacer()
                Text(shortcut).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
