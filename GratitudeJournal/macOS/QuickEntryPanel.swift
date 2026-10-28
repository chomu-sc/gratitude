#if os(macOS)
import AppKit
import SwiftUI
import SwiftData

/// Spotlight / Raycast 처럼 뜨는 플로팅 패널.
///
/// `.nonactivatingPanel` 이 핵심: 패널이 키보드 입력(key)을 받으면서도 앱 전체를 활성화하지 않습니다.
/// → 다른 앱 위에 바로 떠서 입력되고, 메인 윈도우가 같이 튀어나오지 않으며, 닫으면 원래 앱으로 포커스가 돌아갑니다.
final class QuickEntryPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]  // 모든 Space·전체화면 앱 위
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        [.closeButton, .miniaturizeButton, .zoomButton].forEach {
            standardWindowButton($0)?.isHidden = true
        }
    }

    override var canBecomeKey: Bool { true }    // 텍스트 입력 가능하게
    override var canBecomeMain: Bool { false }
}

extension Notification.Name {
    static let quickEntryDidShow = Notification.Name("quickEntryDidShow")
    /// 패널이 닫힐 때 → 그때까지 적은 내용 자동 저장
    static let quickEntryDidHide = Notification.Name("quickEntryDidHide")
}

/// 빠른 작성 패널의 생성·표시·숨김을 담당 (앱 전역 싱글턴)
@MainActor
final class QuickEntryController: NSObject, NSWindowDelegate {
    static let shared = QuickEntryController()

    private var panel: QuickEntryPanel?
    private var escapeMonitor: Any?

    func toggle() {
        if let panel, panel.isVisible, panel.isKeyWindow { hide() } else { show() }
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.makeKeyAndOrderFront(nil)        // NSApp.activate() 호출 안 함 (nonactivating)
        installEscapeMonitor()
        DispatchQueue.main.async {             // 패널이 key가 된 다음 본문에 포커스
            NotificationCenter.default.post(name: .quickEntryDidShow, object: nil)
        }
    }

    func hide() {
        if panel?.isVisible == true {
            NotificationCenter.default.post(name: .quickEntryDidHide, object: nil)
        }
        panel?.orderOut(nil)
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    // 다른 곳을 클릭하면 자동으로 숨김 (작성 중이던 내용은 패널에 그대로 남아있음)
    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    // MARK: - Private

    private func makePanel() -> QuickEntryPanel {
        let root = QuickEntryView(onDone: { [weak self] in self?.hide() })
            .frame(width: 440)
            .background(.regularMaterial)
            .modelContainer(AppContainer.shared)      // 메인 앱과 같은 컨테이너 → 저장 즉시 목록·iCloud 반영

        let hosting = NSHostingView(rootView: root)
        let panel = QuickEntryPanel(contentRect: NSRect(origin: .zero, size: hosting.fittingSize))
        panel.contentView = hosting
        panel.delegate = self
        return panel
    }

    /// 마우스가 있는 화면의 위쪽 1/5 지점 중앙 (Spotlight 위치)
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.maxY - size.height - frame.height * 0.18))
    }

    /// TextEditor(NSTextView)는 esc를 자체 소비하므로 로컬 키 모니터로 확실하게 닫기
    private func installEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53, event.window === self?.panel else { return event }  // 53 = esc
            self?.hide()
            return nil
        }
    }
}
#endif
