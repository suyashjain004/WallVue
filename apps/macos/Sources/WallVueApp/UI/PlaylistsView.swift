import SwiftUI
import WallVueCore

/// The Day Schedule: "like alarms, but for your wallpaper".
struct PlaylistsView: View {
    @Environment(AppModel.self) private var model
    @AppStorage(SettingsKey.scheduleEnabled) private var scheduleEnabled = false
    @AppStorage(SettingsKey.shuffleEnabled) private var shuffleEnabled = false
    @State private var editing: SlotDraft?

    var body: some View {
        PageScroll {
            PageHeader(title: "Playlists", subtitle: "Like alarms, but for your wallpaper: at each time, it changes.") {
                HStack(spacing: 14) {
                    Button {
                        editing = SlotDraft(slot: ScheduleSlot(minutes: Self.currentMinutes()), isNew: true, step: .wallpaper)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(CircleButtonStyle(diameter: 38))
                    .help("Add a time")
                    .accessibilityLabel("Add a time")

                    Toggle("Day Schedule", isOn: $scheduleEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .help(scheduleEnabled ? "The schedule is on" : "Turn the schedule on")
                }
            }

            VStack(spacing: 0) {
                Divider()
                ForEach(model.engine.schedule.slots) { slot in
                    SlotRow(slot: slot) { step in
                        editing = SlotDraft(slot: slot, isNew: false, step: step)
                    }
                    Divider()
                }
            }
            .opacity(scheduleEnabled ? 1 : 0.6)

            if !scheduleEnabled {
                Text("The schedule is off. Turn it on with the switch above; this also turns Shuffle off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: scheduleEnabled) { _, isOn in
            if isOn { shuffleEnabled = false }
        }
        .sheet(item: $editing) { draft in
            SlotEditor(draft: draft)
        }
    }

    private static func currentMinutes() -> Int {
        let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
        return (now.hour ?? 0) * 60 + (now.minute ?? 0)
    }
}

struct SlotDraft: Identifiable {
    enum Step { case wallpaper, time }

    let id = UUID()
    var slot: ScheduleSlot
    var isNew: Bool
    var step: Step
}

private struct SlotRow: View {
    @Environment(AppModel.self) private var model
    let slot: ScheduleSlot
    let edit: (SlotDraft.Step) -> Void

    var body: some View {
        let wallpaper = model.library.wallpaper(id: slot.wallpaperID)
        let clock = slot.clock

        HStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(clock.time)
                        .font(.system(size: 54, weight: .light))
                        .monospacedDigit()
                    Text(clock.meridiem)
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                Text(wallpaper.map { "\(slot.periodLabel) · \($0.title)" } ?? slot.periodLabel)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture { edit(.time) }

            Spacer()

            Button {
                edit(.wallpaper)
            } label: {
                ZStack {
                    if let wallpaper {
                        ThumbnailImage(url: wallpaper.thumbnailURL)
                    } else {
                        Rectangle().fill(.white.opacity(0.06))
                        Image(systemName: "plus").font(.title3)
                    }
                }
                .frame(width: 176, height: 99)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help(wallpaper == nil ? "Choose a wallpaper" : "Change the wallpaper")
            .accessibilityLabel(wallpaper == nil ? "Choose a wallpaper" : "Change the wallpaper")

            Menu {
                Button("Change Wallpaper…") { edit(.wallpaper) }
                Button("Change Time…") { edit(.time) }
                if slot.wallpaperID != nil {
                    Button("Clear Wallpaper") {
                        var cleared = slot
                        cleared.wallpaperID = nil
                        model.engine.updateSlot(cleared)
                    }
                }
                Divider()
                Button("Remove This Time", role: .destructive) { model.engine.removeSlot(slot.id) }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.vertical, 16)
    }
}

/// Two steps, as in the original flow: choose a wallpaper, then pick the time.
private struct SlotEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var draft: SlotDraft
    @State private var search = ""

    var body: some View {
        VStack(spacing: 0) {
            switch draft.step {
            case .wallpaper: wallpaperStep
            case .time: timeStep
            }
        }
        .frame(width: 720, height: 560)
        .preferredColorScheme(.dark)
    }

    private var wallpaperStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Choose a Wallpaper").font(.title.weight(.bold))
                    Text(draft.isNew ? "Next, you'll pick the time it starts." : "It starts at \(draft.slot.clock.time) \(draft.slot.clock.meridiem).")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CircleButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
            }

            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)

            let query = search.trimmingCharacters(in: .whitespaces)
            let items = model.library.wallpapers.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
            if items.isEmpty {
                ContentUnavailableView(
                    model.library.wallpapers.isEmpty ? "Your library is empty" : "No matches",
                    systemImage: "photo.on.rectangle",
                    description: Text(model.library.wallpapers.isEmpty ? "Upload a wallpaper first, then schedule it here." : "Try a different search.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 16)], spacing: 18) {
                        ForEach(items) { wallpaper in
                            Button {
                                draft.slot.wallpaperID = wallpaper.id
                                if draft.isNew {
                                    draft.step = .time
                                } else {
                                    model.engine.updateSlot(draft.slot)
                                    dismiss()
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Color.clear
                                        .aspectRatio(16.0 / 9.0, contentMode: .fit)
                                        .overlay { ThumbnailImage(url: wallpaper.thumbnailURL) }
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(draft.slot.wallpaperID == wallpaper.id ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear), lineWidth: 2)
                                        }
                                    Text(wallpaper.title)
                                        .font(.callout.weight(.semibold))
                                        .lineLimit(1)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(28)
    }

    private var timeStep: some View {
        let wallpaper = model.library.wallpaper(id: draft.slot.wallpaperID)
        return VStack(spacing: 18) {
            HStack {
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(CircleButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Close")
            }

            if let wallpaper {
                ThumbnailImage(url: wallpaper.thumbnailURL)
                    .frame(width: 240, height: 135)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            VStack(spacing: 4) {
                Text("Pick a Time").font(.title.weight(.bold))
                Text(wallpaper?.title ?? "No wallpaper chosen yet").foregroundStyle(.secondary)
            }

            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                .datePickerStyle(.stepperField)
                .labelsHidden()
                .controlSize(.large)
                .scaleEffect(1.4)
                .padding(.vertical, 18)

            Text(draft.slot.periodLabel)
                .font(.callout.weight(.semibold))

            Spacer()

            HStack {
                if draft.isNew {
                    Button("Back") { draft.step = .wallpaper }
                        .buttonStyle(PillButtonStyle(large: true))
                }
                Spacer()
                Button(draft.isNew ? "Add Time" : "Save") {
                    model.engine.updateSlot(draft.slot)
                    dismiss()
                }
                .buttonStyle(PillButtonStyle(prominent: true, large: true))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(
                    bySettingHour: draft.slot.minutes / 60, minute: draft.slot.minutes % 60, second: 0, of: Date()
                ) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                draft.slot.minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}
