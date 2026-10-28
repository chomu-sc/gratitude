#if os(macOS)
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("일반", systemImage: "gearshape") }
            SyncSettingsView()
                .tabItem { Label("동기화", systemImage: "icloud") }
        }
        .frame(width: 460, height: 340)
    }
}

private struct GeneralSettingsView: View {
    @AppStorage(SettingsKeys.hideDockIcon) private var hideDockIcon = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("메뉴 막대") {
                Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = !enabled
                        }
                    }
                Toggle("Dock 아이콘 숨기기 (메뉴 막대에만 표시)", isOn: $hideDockIcon)
                    .onChange(of: hideDockIcon) { _, hide in
                        NSApp.setActivationPolicy(hide ? .accessory : .regular)
                    }
                LabeledContent("빠른 작성 단축키", value: "⌘ ⇧ G")
            }
        }
        .formStyle(.grouped)
    }
}
#endif
