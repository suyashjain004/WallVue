import Foundation
import IOKit.ps

/// Watches the things that should make a wallpaper back off: battery power,
/// Low Power Mode and thermal pressure.
@MainActor
final class PowerMonitor {
    private(set) var onBattery = false
    var onChange: (() -> Void)?

    var lowPowerMode: Bool { ProcessInfo.processInfo.isLowPowerModeEnabled }

    var thermallyConstrained: Bool {
        let state = ProcessInfo.processInfo.thermalState
        return state == .serious || state == .critical
    }

    private var runLoopSource: CFRunLoopSource?
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard runLoopSource == nil else { return }
        refreshPowerSource()

        // IOKit calls back on the run loop we attach the source to (main).
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.refreshPowerSource()
                monitor.onChange?()
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        let center = NotificationCenter.default
        for name in [Notification.Name.NSProcessInfoPowerStateDidChange, ProcessInfo.thermalStateDidChangeNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.onChange?() }
            })
        }
    }

    private func refreshPowerSource() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue()
        else {
            onBattery = false
            return
        }
        onBattery = (type as String) == "Battery Power"
    }
}
