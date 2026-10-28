#if os(macOS)
import Carbon.HIToolbox
import Foundation

/// 시스템 전역 단축키 (다른 앱이 앞에 있어도 동작).
///
/// Carbon의 `RegisterEventHotKey`를 사용하는 이유
/// - '손쉬운 사용(Accessibility)' / '입력 모니터링' 권한이 **필요 없음**
///   (NSEvent.addGlobalMonitorForEvents 방식은 권한 요청 팝업이 뜨고, 키 입력을 '가로채지'는 못함)
/// - App Sandbox 안에서도 동작 → Mac App Store 배포와 dmg(Developer ID) 배포 모두 가능
/// - 등록된 조합은 앞에 있는 앱보다 우선 처리됩니다. (예: Finder의 ⌘⇧G '폴더로 이동'보다 우선)
final class GlobalHotKey {
    struct Modifiers: OptionSet {
        let rawValue: UInt32
        static let command = Modifiers(rawValue: UInt32(cmdKey))
        static let shift   = Modifiers(rawValue: UInt32(shiftKey))
        static let option  = Modifiers(rawValue: UInt32(optionKey))
        static let control = Modifiers(rawValue: UInt32(controlKey))
    }

    private static let signature: OSType = 0x4752_4154   // 'GRAT'
    nonisolated(unsafe) private static var nextID: UInt32 = 1

    private let id: UInt32
    private let action: @MainActor () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    /// - Parameters:
    ///   - keyCode: `kVK_ANSI_G` 같은 가상 키코드 (Carbon.HIToolbox / Events.h)
    ///   - modifiers: 조합키
    /// - Returns: 이미 다른 앱이 같은 조합을 등록한 경우 등 실패 시 nil
    init?(keyCode: Int, modifiers: Modifiers, action: @escaping @MainActor () -> Void) {
        self.id = Self.nextID
        Self.nextID += 1
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        let installStatus = InstallEventHandler(GetApplicationEventTarget(),
                                                Self.eventHandler, 1, &eventType,
                                                userData, &handlerRef)
        guard installStatus == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let registerStatus = RegisterEventHotKey(UInt32(keyCode), modifiers.rawValue, hotKeyID,
                                                 GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registerStatus == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            handlerRef = nil
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }

    /// C 함수 포인터로 넘겨야 하므로 캡처 없는 클로저 + userData로 인스턴스를 되찾습니다.
    private static let eventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }

        var pressedID = EventHotKeyID()
        let status = GetEventParameter(event,
                                       EventParamName(kEventParamDirectObject),
                                       EventParamType(typeEventHotKeyID),
                                       nil,
                                       MemoryLayout<EventHotKeyID>.size,
                                       nil,
                                       &pressedID)
        guard status == noErr else { return status }

        let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
        guard pressedID.signature == GlobalHotKey.signature, pressedID.id == hotKey.id else {
            return OSStatus(eventNotHandledErr)   // 다른 핫키라면 다음 핸들러로 넘김
        }

        let action = hotKey.action
        Task { @MainActor in action() }
        return noErr
    }
}
#endif
