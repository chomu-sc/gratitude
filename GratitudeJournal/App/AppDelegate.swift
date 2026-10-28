#if os(macOS)
import AppKit
import Carbon.HIToolbox
import OSLog

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var quickEntryHotKey: GlobalHotKey?
    private let logger = Logger(subsystem: "GratitudeJournal", category: "HotKey")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 아이콘 숨김 설정 복원 (메뉴 막대 전용 모드)
        if UserDefaults.standard.bool(forKey: SettingsKeys.hideDockIcon) {
            NSApp.setActivationPolicy(.accessory)
        }

        // ⌘ + ⇧ + G 전역 단축키 등록
        quickEntryHotKey = GlobalHotKey(keyCode: kVK_ANSI_G, modifiers: [.command, .shift]) {
            QuickEntryController.shared.toggle()
        }
        if quickEntryHotKey == nil {
            logger.error("⌘⇧G 등록 실패 — 다른 앱이 같은 조합을 이미 전역 등록했을 수 있습니다.")
        }
    }

    /// 창을 모두 닫아도 메뉴 막대에 계속 상주
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    /// Dock 아이콘 클릭 시 창이 없으면 메인 윈도우 다시 열기
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { true }
}

enum SettingsKeys {
    static let hideDockIcon = "hideDockIcon"
}
#endif
