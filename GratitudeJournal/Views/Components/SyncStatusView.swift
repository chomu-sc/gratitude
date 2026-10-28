import SwiftUI

/// 툴바에 표시하는 동기화 상태
struct SyncStatusView: View {
    // @Observable이라 body에서 읽기만 해도 자동 갱신
    private var cloudKit: SyncMonitor { .shared }
    private var cloudSync: CloudSyncService { .shared }

    var body: some View {
        if cloudSync.isSignedIn {
            Label(cloudSync.statusTitle, systemImage: cloudSync.statusSymbol)
                .font(.caption)
                .foregroundStyle(cloudSync.lastError == nil ? Color.secondary : Color.orange)
                .help(cloudSync.lastError ?? "\(cloudSync.email ?? "") 계정으로 iPhone 웹앱과 동기화합니다")
        } else {
            Label(cloudKit.status.title, systemImage: cloudKit.status.symbol)
                .font(.caption)
                .foregroundStyle(cloudKit.status.tint)
                .help(cloudKit.lastError ?? "설정 ▸ 동기화에서 로그인하면 iPhone 웹앱과 기록이 함께 보여요")
        }
    }
}

/// 동기화 설정 (iPhone 앱: 메인 화면 ⚙︎, Mac: 설정 창의 '동기화' 탭)
struct SyncSettingsView: View {
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var message: String?

    private var cloudSync: CloudSyncService { .shared }
    private var cloudKit: SyncMonitor { .shared }

    var body: some View {
        Form {
            if !SupabaseConfig.isConfigured {
                Section("동기화") {
                    Text("AppContainer.swift의 SupabaseConfig에 주소와 키를 넣으면 iPhone 웹앱과 기록을 함께 볼 수 있어요.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else if cloudSync.isSignedIn {
                Section("계정") {
                    LabeledContent("이메일", value: cloudSync.email ?? "")
                    LabeledContent("상태") {
                        Label(cloudSync.statusTitle, systemImage: cloudSync.statusSymbol)
                    }
                    if let error = cloudSync.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Button("지금 동기화") { cloudSync.syncNow() }
                        .disabled(cloudSync.isSyncing)
                    Button("로그아웃", role: .destructive) { cloudSync.signOut() }
                }
            } else {
                Section {
                    TextField("이메일", text: $email)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                    SecureField("비밀번호 (6자 이상)", text: $password)
                        .textContentType(.password)
                        .onSubmit { submit(signUp: false) }
                    HStack {
                        Button("로그인") { submit(signUp: false) }
                            .buttonStyle(.borderedProminent)
                        Button("계정 만들기") { submit(signUp: true) }
                        if isWorking { ProgressView().controlSize(.small) }
                    }
                    .disabled(isWorking || email.isEmpty || password.count < 6)
                    if let message {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("iPhone 웹앱과 같은 계정으로 로그인")
                } footer: {
                    Text("로그인하면 이 기기에 이미 적어 둔 일기도 함께 올라가요.")
                }
            }

            if AppContainer.isCloudSyncEnabled {
                Section("CloudKit") {
                    LabeledContent("상태", value: cloudKit.status.title)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func submit(signUp: Bool) {
        let email = email.trimmingCharacters(in: .whitespaces)
        guard !email.isEmpty, password.count >= 6, !isWorking else { return }
        isWorking = true
        message = nil
        Task {
            do {
                if signUp {
                    let signedIn = try await cloudSync.signUp(email: email, password: password)
                    if !signedIn {
                        message = "확인 메일을 보냈어요. 메일의 링크를 누른 뒤 [로그인]을 눌러 주세요."
                    }
                } else {
                    try await cloudSync.signIn(email: email, password: password)
                }
                password = ""
            } catch {
                message = error.localizedDescription
            }
            isWorking = false
        }
    }
}
