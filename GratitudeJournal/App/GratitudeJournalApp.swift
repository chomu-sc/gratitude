import SwiftUI
import SwiftData

@main
struct GratitudeJournalApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif

    init() {
        SyncMonitor.shared.start()          // CloudKit 상태 (유료 계정 + 스위치 켰을 때만 동작)
        CloudSyncService.shared.start()     // Supabase 동기화 (주소·키를 넣고 로그인했을 때만 동작)
    }

    var body: some Scene {
        // 1) 메인 윈도우 (iOS · macOS 공통)
        WindowGroup(id: "main") {
            ContentView()
        }
        .modelContainer(AppContainer.shared)
        #if os(macOS)
        .defaultSize(width: 920, height: 720)
        .commands {
            CommandGroup(after: .newItem) {
                // 실제 단축키(⌘⇧G)는 AppDelegate의 전역 단축키가 처리합니다. 메뉴엔 표시만.
                Button("빠른 감사일기 작성 (⌘⇧G)") { QuickEntryController.shared.toggle() }
            }
        }
        #endif

        #if os(macOS)
        // 2) 메뉴 막대 상주 아이콘
        MenuBarExtra {
            MenuBarContentView()
                .modelContainer(AppContainer.shared)
        } label: {
            Image(systemName: "face.smiling")   // 템플릿 이미지 → 다크/라이트 메뉴 막대에 자동 대응
        }
        .menuBarExtraStyle(.window)

        // 3) 환경설정 (⌘,)
        Settings {
            SettingsView()
        }
        #endif
    }
}
