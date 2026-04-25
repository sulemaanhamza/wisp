import AppKit
import Carbon.HIToolbox

/// Wraps Carbon's RegisterEventHotKey so we can listen for a system-wide
/// keypress without requesting Accessibility permission.
///
/// Modern alternatives (NSEvent.addGlobalMonitorForEvents) require the user
/// to grant Accessibility access; Carbon does not. The API is C and a bit
/// crusty, but a thin wrapper is well under 100 lines.
@MainActor
final class HotKeyMonitor {
    private var hotKeyRef: EventHotKeyRef?
    private let id: UInt32

    private static var nextID: UInt32 = 1
    private static var eventHandlerInstalled = false
    // The Carbon callback fires on the main run loop but isn't formally
    // MainActor-isolated. We only mutate this dict from MainActor methods,
    // so reads from the callback are safe in practice.
    private static nonisolated(unsafe) var handlers: [UInt32: () -> Void] = [:]

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    // No deinit cleanup: HotKeyMonitor is held by AppDelegate for the
    // app's entire lifetime, so the hotkey naturally goes away on quit.

    /// Register a system-wide hotkey. Returns true on success.
    /// `keyCode` is a Carbon kVK_* value; `modifiers` is an OR of cmdKey /
    /// shiftKey / optionKey / controlKey from Carbon.
    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) -> Bool {
        Self.installSharedEventHandler()
        Self.handlers[id] = handler

        let signature: OSType = 0x57495350  // 'WISP'
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )
        return status == noErr
    }

    private static func installSharedEventHandler() {
        guard !eventHandlerInstalled else { return }
        eventHandlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, event, _) -> OSStatus in
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
                guard status == noErr,
                      let handler = HotKeyMonitor.handlers[hotKeyID.id]
                else { return noErr }
                DispatchQueue.main.async { handler() }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}
