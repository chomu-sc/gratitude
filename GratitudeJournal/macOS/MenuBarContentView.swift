#if os(macOS)
import SwiftUI
import SwiftData

/// 메뉴 막대 아이콘 클릭 시 열리는 창 (.menuBarExtraStyle(.window))
struct MenuBarContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 0) {
            QuickEntryView()

            Divider()

            HStack(spacing: 12) {
                SyncStatusView()
                Spacer()
                Button("캘린더 열기") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                SettingsLink { Image(systemName: "gearshape") }
                Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                    .help("종료")
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 400)
    }
}
#endif
