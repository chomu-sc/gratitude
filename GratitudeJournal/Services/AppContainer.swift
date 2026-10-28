import Foundation
import SwiftData
import OSLog

/// iPhone 웹앱과 함께 쓰는 Supabase 데이터베이스 정보
/// Supabase ▸ Project Settings ▸ API 에서 복사해 넣으세요. (웹앱 config.js와 같은 값)
/// 비워 두면 이 기기에만 저장합니다.
enum SupabaseConfig {
    static let url = "https://lyxndiiuaugtbafvzqff.supabase.co/rest/v1/"        // 예: "https://abcdefghijk.supabase.co"
    static let anonKey = "sb_publishable_Wr-O9B8Fnyz4QwCgKXj8uw_eEMTB4do"    // anon public 키 (공개돼도 되는 키 — 데이터는 로그인한 본인만 접근 가능)

    static var isConfigured: Bool {
        URL(string: url)?.host != nil && !anonKey.isEmpty
    }
}

/// 앱 전체(메인 윈도우, 메뉴 막대, 빠른 작성 패널)가 **하나의** ModelContainer를 공유해야
/// 어느 창에서 저장하든 다른 창의 @Query가 즉시 갱신됩니다.
enum AppContainer {
    /// iCloud 동기화 스위치.
    /// - false: CloudKit API를 전혀 호출하지 않고 이 기기에만 저장합니다. (무료 Apple ID / iCloud 미설정 시)
    /// - true : Signing & Capabilities 에 iCloud(CloudKit) 를 추가한 **뒤에만** 켜세요.
    ///          엔타이틀먼트 없이 켜면 CloudKit이 앱을 즉시 종료시킵니다(try/catch로 잡히지 않음).
    static let isCloudSyncEnabled = false

    /// ⚠️ Xcode > Signing & Capabilities > iCloud 에서 만든 컨테이너 ID와 정확히 같아야 합니다.
    static let cloudKitContainerID = "iCloud.com.yourname.GratitudeJournal"

    private static let logger = Logger(subsystem: "GratitudeJournal", category: "Persistence")

    static let shared: ModelContainer = {
        let schema = Schema([GratitudeEntry.self])
        let config = ModelConfiguration(
            "GratitudeJournal",
            schema: schema,
            // 같은 저장소 이름을 쓰므로, 나중에 동기화를 켜면 로컬에 쓴 일기가 그대로 iCloud로 올라갑니다.
            cloudKitDatabase: isCloudSyncEnabled ? .private(cloudKitContainerID) : .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // 엔타이틀먼트 누락·스키마 오류 등. 앱이 죽지 않도록 로컬 전용으로 대체하되 로그로 크게 알립니다.
            logger.fault("CloudKit 컨테이너 생성 실패, 로컬 저장소로 대체: \(error.localizedDescription)")
            let localConfig = ModelConfiguration("GratitudeJournal-Local", schema: schema, cloudKitDatabase: .none)
            do {
                return try ModelContainer(for: schema, configurations: [localConfig])
            } catch {
                fatalError("ModelContainer를 만들 수 없습니다: \(error)")
            }
        }
    }()

    /// SwiftUI 프리뷰용 인메모리 컨테이너
    @MainActor
    static let preview: ModelContainer = {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try! ModelContainer(for: GratitudeEntry.self, configurations: config)
        let samples: [(Int, Int, [String], String?)] = [
            (0, 6, ["아침에 마신 따뜻한 라떼", "퇴근길 노을이 예뻤다"], "작은 것들이 하루를 채워준 날"),
            (1, 3, ["힘든 회의였지만 동료가 커피를 사줬다"], nil),
            (3, 7, ["오랜만에 가족과 저녁을 먹었다", "엄마가 반찬을 싸주셨다", "푹 잤다"], "웃음이 많았던 저녁"),
        ]
        for (daysAgo, level, items, summary) in samples {
            let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!
            container.mainContext.insert(
                GratitudeEntry(day: date, items: items, emotionLevel: level, summary: summary)
            )
        }
        return container
    }()
}
