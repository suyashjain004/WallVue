import Darwin
import Foundation
import Observation
import WallVueCore

/// The app's own footprint, shown in the menu bar panel so anyone can see
/// what a live wallpaper is costing them.
@MainActor
@Observable
final class ProcessStats {
    private(set) var cpuPercent = 0
    private(set) var memoryMB = 0
    private(set) var cacheMB = 0

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var lastCPUTime: Double = 0
    @ObservationIgnored private var lastSample = Date()

    /// Sampling only runs while something is showing the numbers.
    func start() {
        guard timer == nil else { return }
        lastCPUTime = Self.cpuSeconds()
        lastSample = Date()
        sample()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sample() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        let now = Date()
        let cpu = Self.cpuSeconds()
        let elapsed = now.timeIntervalSince(lastSample)
        if elapsed > 0.2 {
            cpuPercent = max(0, Int(((cpu - lastCPUTime) / elapsed * 100).rounded()))
        }
        lastCPUTime = cpu
        lastSample = now
        memoryMB = Self.footprintMB()
        cacheMB = Int(AppPaths.size(of: AppPaths.thumbnails) / 1_048_576)
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1_048_576)
    }
}
