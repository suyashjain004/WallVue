import Foundation

/// One entry in the day schedule: "at this time, switch to this wallpaper".
public struct ScheduleSlot: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    /// Minutes after midnight, 0..<1440.
    public var minutes: Int
    public var wallpaperID: UUID?

    public init(id: UUID = UUID(), minutes: Int, wallpaperID: UUID? = nil) {
        self.id = id
        self.minutes = ((minutes % 1440) + 1440) % 1440
        self.wallpaperID = wallpaperID
    }

    public var periodLabel: String { DaySchedule.periodLabel(forMinutes: minutes) }

    /// Hour and minute in 12-hour form plus AM/PM, e.g. ("7:00", "AM").
    public var clock: (time: String, meridiem: String) {
        let hour24 = minutes / 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return (String(format: "%d:%02d", hour12, minutes % 60), hour24 < 12 ? "AM" : "PM")
    }
}

/// "Like alarms, but for your wallpaper": at each time, it changes.
public struct DaySchedule: Codable, Equatable, Sendable {
    public var slots: [ScheduleSlot]

    public init(slots: [ScheduleSlot] = DaySchedule.defaultSlots) {
        self.slots = slots.sorted { $0.minutes < $1.minutes }
    }

    public static var defaultSlots: [ScheduleSlot] {
        [7 * 60, 12 * 60, 18 * 60, 22 * 60].map { ScheduleSlot(minutes: $0) }
    }

    public static func periodLabel(forMinutes minutes: Int) -> String {
        switch minutes / 60 {
        case 5..<12: return "Morning"
        case 12..<17: return "Afternoon"
        case 17..<21: return "Evening"
        case 21..<24: return "Night"
        default: return "Late Night"
        }
    }

    /// The slot in force at `minutes` after midnight: the latest slot that
    /// has a wallpaper and has already started today, otherwise the last
    /// such slot of the previous day.
    public func activeSlot(atMinutes minutes: Int) -> ScheduleSlot? {
        let filled = slots.filter { $0.wallpaperID != nil }.sorted { $0.minutes < $1.minutes }
        return filled.last { $0.minutes <= minutes } ?? filled.last
    }

    public mutating func upsert(_ slot: ScheduleSlot) {
        slots.removeAll { $0.id == slot.id }
        slots.append(slot)
        slots.sort { $0.minutes < $1.minutes }
    }

    public mutating func remove(_ id: UUID) {
        slots.removeAll { $0.id == id }
    }

    /// Clears references to wallpapers that no longer exist.
    public mutating func prune(keeping valid: Set<UUID>) {
        for index in slots.indices {
            if let id = slots[index].wallpaperID, !valid.contains(id) { slots[index].wallpaperID = nil }
        }
    }

    public static func load(from url: URL = AppPaths.scheduleFile) -> DaySchedule {
        guard let data = try? Data(contentsOf: url),
              let schedule = try? JSONDecoder().decode(DaySchedule.self, from: data)
        else { return DaySchedule() }
        return schedule
    }

    public func save(to url: URL = AppPaths.scheduleFile) {
        AppPaths.ensureDirectories()
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
