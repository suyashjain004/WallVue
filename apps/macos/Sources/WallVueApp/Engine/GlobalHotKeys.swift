import AppKit
import Carbon.HIToolbox

/// Keyboard shortcuts that work while another app is in front.
///
/// Uses the Carbon hot-key API, which needs no Accessibility permission.
@MainActor
final class GlobalHotKeys {
    struct Binding {
        let keyCode: Int
        let modifiers: Int
        let action: @MainActor () -> Void
    }

    private var hotKeys: [EventHotKeyRef] = []
    private var actions: [UInt32: @MainActor () -> Void] = [:]
    private var handler: EventHandlerRef?

    /// 'WVUE'
    private static let signature: OSType = 0x5756_5545

    var isRegistered: Bool { !hotKeys.isEmpty }

    /// Replaces any existing shortcuts with `bindings`.
    func register(_ bindings: [Binding]) {
        unregisterAll()
        installHandlerIfNeeded()
        for (index, binding) in bindings.enumerated() {
            let id = UInt32(index + 1)
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                UInt32(binding.keyCode),
                UInt32(binding.modifiers),
                EventHotKeyID(signature: Self.signature, id: id),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            // A shortcut another app already owns simply isn't registered.
            if status == noErr, let reference {
                hotKeys.append(reference)
                actions[id] = binding.action
            }
        }
    }

    func unregisterAll() {
        for hotKey in hotKeys { UnregisterEventHotKey(hotKey) }
        hotKeys = []
        actions = [:]
    }

    fileprivate func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let id = hotKeyID.id
                let owner = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hot-key events on the main thread.
                MainActor.assumeIsolated { owner.fire(id) }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }
}
