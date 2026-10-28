import Foundation
import CoreData
import CloudKit
import Observation
import Security
import SwiftData
import SwiftUI

/// iCloud 동기화 상태 관찰자.
///
/// SwiftData의 CloudKit 동기화는 내부적으로 NSPersistentCloudKitContainer가 수행하므로,
/// 그 이벤트 알림(eventChangedNotification)을 구독해 setup / import / export 진행 상황을 UI에 보여줄 수 있습니다.
/// 실제 데이터 병합은 자동입니다: 다른 기기에서 저장 → 무음 푸시 → import → @Query 자동 갱신.
@MainActor
@Observable
final class SyncMonitor {
    enum Status: Equatable {
        case idle
        case localOnly
        case syncing
        case synced(Date)
        case noAccount
        case failed(String)

        var title: String {
            switch self {
            case .idle:            "동기화 대기"
            case .localOnly:       "이 기기에만 저장"
            case .syncing:         "동기화 중…"
            case .synced(let d):   "동기화됨 · \(d.formatted(.relative(presentation: .named)))"
            case .noAccount:       "iCloud 로그인 필요"
            case .failed:          "동기화 오류"
            }
        }

        var symbol: String {
            switch self {
            case .idle:      "icloud"
            case .localOnly: "internaldrive"
            case .syncing:   "arrow.triangle.2.circlepath.icloud"
            case .synced:    "checkmark.icloud"
            case .noAccount: "icloud.slash"
            case .failed:    "exclamationmark.icloud"
            }
        }

        var tint: Color {
            switch self {
            case .failed, .noAccount: .orange
            default: .secondary
            }
        }
    }

    static let shared = SyncMonitor()

    private(set) var status: Status = .idle
    private(set) var lastError: String?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        // 엔타이틀먼트가 없을 때 CKContainer를 만들면 앱이 즉시 종료되므로 아예 건드리지 않습니다.
        guard AppContainer.isCloudSyncEnabled else {
            status = .localOnly
            return
        }

        Task { [weak self] in
            let events = NotificationCenter.default.notifications(
                named: NSPersistentCloudKitContainer.eventChangedNotification
            )
            for await note in events {
                guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { continue }
                self?.handle(event)
            }
        }

        Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                await self?.refreshAccountStatus()
            }
        }

        Task { await refreshAccountStatus() }
    }

    private func handle(_ event: NSPersistentCloudKitContainer.Event) {
        if event.endDate == nil {
            status = .syncing
        } else if event.succeeded {
            status = .synced(event.endDate ?? .now)
            lastError = nil
        } else {
            let message = event.error?.localizedDescription ?? "알 수 없는 오류"
            lastError = message
            status = .failed(message)
        }
    }

    func refreshAccountStatus() async {
        do {
            let account = try await CKContainer(identifier: AppContainer.cloudKitContainerID).accountStatus()
            if account != .available {
                status = .noAccount
            } else if status == .noAccount {
                status = .idle
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}

// MARK: - Supabase 동기화 (iPhone 웹앱과 같은 데이터베이스)

/// 웹앱과 같은 Supabase `entries` 테이블을 읽고 씁니다. (무료 Apple ID로 OK)
///
/// - 로그인: 웹앱과 같은 이메일/비밀번호. 로그인 정보는 Keychain에 저장되어 앱을 다시 켜도 유지됩니다.
/// - 반영: 저장/삭제 즉시 업로드 + 30초마다·앱을 열 때마다 내려받기
/// - 충돌: 같은 날짜를 두 기기에서 고치면 나중에 저장한 쪽이 이깁니다. (DB 트리거도 같은 규칙)
/// - 삭제: deleted 표시로 남겨서 다른 기기에서도 지워지게 합니다.
@MainActor
@Observable
final class CloudSyncService {
    static let shared = CloudSyncService()

    private(set) var session: AuthSession?
    private(set) var lastSync: Date?
    private(set) var isSyncing = false
    private(set) var lastError: String?

    var isSignedIn: Bool { session != nil }
    var email: String? { session?.email }

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false
    private var context: ModelContext { AppContainer.shared.mainContext }

    private init() {}

    func start() {
        guard !started, SupabaseConfig.isConfigured else { return }
        started = true
        session = KeychainStore.loadSession()
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in
            Task { @MainActor in CloudSyncService.shared.syncNow() }
        }
        syncNow()
    }

    // MARK: 로그인

    func signIn(email: String, password: String) async throws {
        let response: AuthResponse = try await authRequest(
            path: "token?grant_type=password", body: ["email": email, "password": password])
        try adopt(response)
        syncNow()
    }

    /// - Returns: 바로 로그인됐으면 true, 확인 메일을 눌러야 하면 false
    func signUp(email: String, password: String) async throws -> Bool {
        let response: AuthResponse = try await authRequest(
            path: "signup", body: ["email": email, "password": password])
        guard response.access_token != nil else { return false }
        try adopt(response)
        syncNow()
        return true
    }

    func signOut() {
        session = nil
        lastSync = nil
        lastError = nil
        KeychainStore.deleteSession()
    }

    // MARK: 동기화

    /// 서버 전체와 이 기기를 비교해 서로 최신 상태로 맞춥니다.
    func syncNow() {
        guard SupabaseConfig.isConfigured, session != nil, !isSyncing else { return }
        isSyncing = true
        Task {
            do {
                let remote = try await fetchAll()
                let outgoing = reconcile(with: remote)
                try await upsert(outgoing)
                lastError = nil
                lastSync = .now
            } catch {
                lastError = error.localizedDescription
            }
            isSyncing = false
        }
    }

    /// 이 기기에서 저장/삭제한 직후 → 그 날짜만 바로 업로드
    func didChange(day: Date) {
        guard SupabaseConfig.isConfigured, session != nil else { return }
        let entries = (try? EntryRepository(context: context).entries(on: day)) ?? []
        let row: RemoteEntry
        if let entry = entries.last {
            row = makeRow(from: entry)
        } else {
            row = RemoteEntry(day: Self.key(for: day), items: [], emotionLevel: GratitudeEntry.unsetEmotion,
                              summary: nil, updatedAt: SupabaseDate.string(.now), deleted: true)
        }
        Task {
            do {
                try await upsert([row])
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// 서버 → 이 기기 반영은 여기서 바로 하고, 서버로 올려야 할 줄 목록을 돌려줍니다.
    private func reconcile(with remoteRows: [RemoteEntry]) -> [RemoteEntry] {
        var remote: [String: RemoteEntry] = [:]
        for row in remoteRows { remote[row.day] = row }

        // 날짜별 이 기기 기록 (중복이 있으면 최신 것만 남김)
        var local: [String: GratitudeEntry] = [:]
        for entry in (try? context.fetch(FetchDescriptor<GratitudeEntry>())) ?? [] {
            let key = Self.key(for: entry.day)
            if let kept = local[key] {
                if kept.updatedAt >= entry.updatedAt {
                    context.delete(entry)
                    continue
                }
                context.delete(kept)
            }
            local[key] = entry
        }

        var outgoing: [RemoteEntry] = []
        for key in Set(local.keys).union(remote.keys) {
            switch (local[key], remote[key]) {
            case let (entry?, nil):
                outgoing.append(makeRow(from: entry))
            case let (nil, row?):
                if !row.deleted, let day = Self.date(from: key) { insert(row, day: day) }
            case let (entry?, row?):
                let remoteTime = SupabaseDate.parse(row.updatedAt) ?? .distantPast
                let diff = remoteTime.timeIntervalSince(entry.updatedAt)
                if diff > 0.5 {
                    apply(row, to: entry, updatedAt: remoteTime)     // 서버 쪽이 최신
                } else if diff < -0.5 {
                    outgoing.append(makeRow(from: entry))           // 이 기기 쪽이 최신
                }
            case (nil, nil):
                break
            }
        }
        try? context.save()
        return outgoing
    }

    private func apply(_ row: RemoteEntry, to entry: GratitudeEntry, updatedAt: Date) {
        if row.deleted {
            context.delete(entry)
            return
        }
        entry.items = row.items
        entry.emotionLevel = row.emotionLevel
        entry.summary = row.summary
        entry.updatedAt = updatedAt
    }

    private func insert(_ row: RemoteEntry, day: Date) {
        let entry = GratitudeEntry(day: day, items: row.items, emotionLevel: 4, summary: row.summary)
        entry.emotionLevel = row.emotionLevel
        entry.updatedAt = SupabaseDate.parse(row.updatedAt) ?? .now
        context.insert(entry)
    }

    private func makeRow(from entry: GratitudeEntry) -> RemoteEntry {
        RemoteEntry(day: Self.key(for: entry.day), items: entry.items, emotionLevel: entry.emotionLevel,
                    summary: entry.summary, updatedAt: SupabaseDate.string(entry.updatedAt), deleted: false)
    }

    // MARK: 네트워크

    private struct AuthResponse: Decodable {
        struct User: Decodable {
            let id: String
            let email: String?
        }
        let access_token: String?
        let refresh_token: String?
        let expires_in: Double?
        let user: User?
    }

    enum SyncError: LocalizedError {
        case server(Int, String)
        case notSignedIn

        var errorDescription: String? {
            switch self {
            case .server(_, let message): return message
            case .notSignedIn: return "로그인이 필요해요."
            }
        }
    }

    private func adopt(_ response: AuthResponse) throws {
        guard let access = response.access_token, let refresh = response.refresh_token, let user = response.user else {
            throw SyncError.server(0, "로그인 정보를 받지 못했어요.")
        }
        let newSession = AuthSession(accessToken: access, refreshToken: refresh,
                                     expiresAt: Date().addingTimeInterval(response.expires_in ?? 3600),
                                     userID: user.id, email: user.email ?? "")
        session = newSession
        KeychainStore.saveSession(newSession)
        lastError = nil
    }

    /// 만료가 가까우면 자동으로 새 토큰을 받아옴
    private func validAccessToken() async throws -> String {
        guard let current = session else { throw SyncError.notSignedIn }
        if current.expiresAt.timeIntervalSinceNow > 60 { return current.accessToken }
        do {
            let response: AuthResponse = try await authRequest(
                path: "token?grant_type=refresh_token", body: ["refresh_token": current.refreshToken])
            try adopt(response)
            return response.access_token ?? current.accessToken
        } catch SyncError.server(let status, _) where (400..<500).contains(status) {
            signOut()   // 로그인이 만료됨 → 다시 로그인 필요
            throw SyncError.server(status, "로그인이 만료됐어요. 다시 로그인해 주세요.")
        }
    }

    private func authRequest<T: Decodable>(path: String, body: [String: String]) async throws -> T {
        var request = URLRequest(url: URL(string: "\(SupabaseConfig.url)/auth/v1/\(path)")!)
        request.httpMethod = "POST"
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func restRequest(_ method: String, query: String, body: Data? = nil, prefer: String? = nil) async throws -> Data {
        let token = try await validAccessToken()
        var request = URLRequest(url: URL(string: "\(SupabaseConfig.url)/rest/v1/entries?\(query)")!)
        request.httpMethod = method
        request.setValue(SupabaseConfig.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let prefer { request.setValue(prefer, forHTTPHeaderField: "Prefer") }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.check(response, data)
        return data
    }

    private func fetchAll() async throws -> [RemoteEntry] {
        let data = try await restRequest("GET", query: "select=day,items,emotion_level,summary,updated_at,deleted")
        return try JSONDecoder().decode([RemoteEntry].self, from: data)
    }

    private func upsert(_ rows: [RemoteEntry]) async throws {
        guard !rows.isEmpty, let userID = session?.userID else { return }
        let payload = rows.map { row -> RemoteEntry in
            var copy = row
            copy.userID = userID
            return copy
        }
        _ = try await restRequest("POST", query: "on_conflict=user_id,day",
                                  body: try JSONEncoder().encode(payload),
                                  prefer: "resolution=merge-duplicates,return=minimal")
    }

    private static func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) else { return }
        var message = String(data: data, encoding: .utf8) ?? "서버 오류 (\(http.statusCode))"
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error_description", "msg", "message", "error"] {
                if let text = object[key] as? String { message = text; break }
            }
        }
        throw SyncError.server(http.statusCode, friendly(message))
    }

    private static func friendly(_ message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("invalid login") { return "이메일 또는 비밀번호가 맞지 않아요." }
        if lower.contains("email not confirmed") { return "메일함의 확인 링크를 먼저 눌러 주세요." }
        if lower.contains("already registered") { return "이미 가입된 이메일이에요. 로그인해 주세요." }
        if lower.contains("password should be") { return "비밀번호는 6자 이상이어야 해요." }
        return message
    }

    // MARK: 표시용

    var statusTitle: String {
        if isSyncing { return "동기화 중…" }
        if lastError != nil { return "동기화 오류" }
        if let lastSync { return "동기화됨 · \(lastSync.formatted(date: .omitted, time: .shortened))" }
        return "동기화 대기"
    }

    var statusSymbol: String {
        if isSyncing { return "arrow.triangle.2.circlepath" }
        if lastError != nil { return "exclamationmark.icloud" }
        return "checkmark.icloud"
    }

    // MARK: 날짜 키 ("2026-10-28")

    private static let keyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func key(for day: Date) -> String { keyFormatter.string(from: day) }
    static func date(from key: String) -> Date? { keyFormatter.date(from: key) }
}

/// 로그인 정보 (Keychain에 저장)
struct AuthSession: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String
    var email: String
}

/// Supabase entries 테이블의 한 줄 (= 하루)
struct RemoteEntry: Codable, Sendable {
    var userID: String?
    var day: String
    var items: [String]
    var emotionLevel: Int
    var summary: String?
    var updatedAt: String
    var deleted: Bool

    init(userID: String? = nil, day: String, items: [String], emotionLevel: Int,
         summary: String?, updatedAt: String, deleted: Bool) {
        self.userID = userID
        self.day = day
        self.items = items
        self.emotionLevel = emotionLevel
        self.summary = summary
        self.updatedAt = updatedAt
        self.deleted = deleted
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id", day, items, emotionLevel = "emotion_level", summary, updatedAt = "updated_at", deleted
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userID = try c.decodeIfPresent(String.self, forKey: .userID)
        day = try c.decode(String.self, forKey: .day)
        items = try c.decodeIfPresent([String].self, forKey: .items) ?? []
        emotionLevel = try c.decodeIfPresent(Int.self, forKey: .emotionLevel) ?? 0
        summary = try c.decodeIfPresent(String.self, forKey: .summary)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        deleted = try c.decodeIfPresent(Bool.self, forKey: .deleted) ?? false
    }

    /// 여러 줄을 한 번에 올릴 때 모든 줄의 키가 같아야 하므로 summary가 없어도 null로 보냄
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(userID, forKey: .userID)
        try c.encode(day, forKey: .day)
        try c.encode(items, forKey: .items)
        try c.encode(emotionLevel, forKey: .emotionLevel)
        try c.encode(summary, forKey: .summary)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(deleted, forKey: .deleted)
    }
}

/// Postgres timestamptz ⇄ Date
enum SupabaseDate {
    nonisolated(unsafe) private static let withFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    nonisolated(unsafe) private static let plain = ISO8601DateFormatter()

    static func string(_ date: Date) -> String { withFraction.string(from: date) }
    static func parse(_ text: String) -> Date? { withFraction.date(from: text) ?? plain.date(from: text) }
}

/// 로그인 정보를 Keychain에 보관
enum KeychainStore {
    private static let service = "GratitudeJournal.supabase"
    private static let account = "session"

    static func saveSession(_ session: AuthSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        deleteSession()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadSession() -> AuthSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(AuthSession.self, from: data)
    }

    static func deleteSession() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
