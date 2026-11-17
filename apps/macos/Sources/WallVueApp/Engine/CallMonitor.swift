import CoreAudio
import CoreMediaIO
import Foundation

/// Notices when the Mac is busy with a call or a screen share: a camera or
/// microphone in use, or the screen being captured. It only reads the
/// system's "in use" flags; it never opens a camera, a microphone or the
/// screen itself, so it needs no permission and sees and hears nothing.
@MainActor
final class CallMonitor {
    struct Signals: Equatable, Sendable {
        var camera = false
        var microphone = false
        var screen = false
    }

    /// What is in use right now, limited to the things being watched.
    private(set) var signals = Signals()
    var onChange: (() -> Void)?

    private var watched = Signals()
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "io.github.wallvue.calls", qos: .utility)

    /// Chooses what to watch. Watching nothing stops the checks entirely.
    func watch(camera: Bool, microphone: Bool, screen: Bool) {
        let wanted = Signals(camera: camera, microphone: microphone, screen: screen)
        guard wanted != watched else { return }
        watched = wanted
        timer?.cancel()
        timer = nil

        guard wanted != Signals() else {
            publish(Signals(), for: wanted)
            return
        }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: .seconds(2), leeway: .milliseconds(500))
        source.setEventHandler { [weak self] in
            let sample = Signals(
                camera: wanted.camera && Self.cameraInUse(),
                microphone: wanted.microphone && Self.microphoneInUse(),
                screen: wanted.screen && Self.screenIsCaptured()
            )
            Task { @MainActor in self?.publish(sample, for: wanted) }
        }
        source.resume()
        timer = source
    }

    private func publish(_ sample: Signals, for wanted: Signals) {
        // A check that started before the choice changed is out of date.
        guard wanted == watched, sample != signals else { return }
        signals = sample
        onChange?()
    }

    // MARK: Reading the system's flags

    nonisolated static func cameraInUse() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == 0, size > 0 else { return false }
        var devices = [CMIODeviceID](repeating: 0, count: Int(size) / MemoryLayout<CMIODeviceID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &devices) == 0 else { return false }

        for device in devices {
            var running: UInt32 = 0
            var usedSize: UInt32 = 0
            var runningAddress = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            let status = CMIOObjectGetPropertyData(
                device, &runningAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &usedSize, &running
            )
            if status == 0, running != 0 { return true }
        }
        return false
    }

    nonisolated static func microphoneInUse() -> Bool {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &devices) == noErr else { return false }

        for device in devices {
            // Only devices that can record count; speakers are "running"
            // whenever anything plays sound.
            var streams = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioDevicePropertyScopeInput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }

            var running: UInt32 = 0
            var runningSize = UInt32(MemoryLayout<UInt32>.size)
            var runningAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            if AudioObjectGetPropertyData(device, &runningAddress, 0, nil, &runningSize, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }

    private typealias WatcherCheck = @convention(c) () -> Bool

    /// macOS has no public "is the screen being captured" flag. The window
    /// server has a private one; it is looked up by name at run time, so if
    /// a future macOS drops it this simply reports false.
    private nonisolated static let watcherCheck: WatcherCheck? = {
        let anyLoadedLibrary = UnsafeMutableRawPointer(bitPattern: -2)   // RTLD_DEFAULT
        guard let symbol = dlsym(anyLoadedLibrary, "CGSIsScreenWatcherPresent") else { return nil }
        return unsafeBitCast(symbol, to: WatcherCheck.self)
    }()

    nonisolated static var canDetectScreenCapture: Bool { watcherCheck != nil }

    nonisolated static func screenIsCaptured() -> Bool {
        watcherCheck?() ?? false
    }
}
