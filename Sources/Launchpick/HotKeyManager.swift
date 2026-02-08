import Carbon
import Cocoa

class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeys: [UInt32: (ref: EventHotKeyRef, handler: () -> Void)] = [:]
    private var handlerRef: EventHandlerRef?

    private func ensureHandler() {
        guard handlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            selfPtr,
            &handlerRef
        )
    }

    func register(id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        unregister(id: id)
        ensureHandler()

        let hotKeyID = EventHotKeyID(
            signature: fourCharCode("LNCH"),
            id: id
        )

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        if status == noErr, let ref = ref {
            hotKeys[id] = (ref: ref, handler: handler)
            NSLog("HotKeyManager: registered id=\(id) keyCode=\(keyCode) modifiers=\(modifiers)")
        } else {
            NSLog("HotKeyManager: FAILED to register id=\(id) keyCode=\(keyCode) modifiers=\(modifiers) status=\(status)")
        }
    }

    func unregister(id: UInt32) {
        if let entry = hotKeys.removeValue(forKey: id) {
            UnregisterEventHotKey(entry.ref)
        }
    }

    func unregisterAll() {
        for (_, entry) in hotKeys {
            UnregisterEventHotKey(entry.ref)
        }
        hotKeys.removeAll()
        if let ref = handlerRef {
            RemoveEventHandler(ref)
            handlerRef = nil
        }
    }

    fileprivate func handleHotKey(event: EventRef) {
        var hotKeyID = EventHotKeyID()
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )

        NSLog("HotKeyManager: hotkey fired id=\(hotKeyID.id)")
        if let entry = hotKeys[hotKeyID.id] {
            entry.handler()
        }
    }
}

private func hotKeyEventHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let userData = userData, let event = event else { return OSStatus(eventNotHandledErr) }
    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKey(event: event)
    return noErr
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for char in string.utf8.prefix(4) {
        result = (result << 8) + FourCharCode(char)
    }
    return result
}
