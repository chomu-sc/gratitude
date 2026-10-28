import Foundation
import SwiftData

/// 일기 저장/조회를 한 곳에 모은 얇은 서비스 계층.
/// 뷰는 이 타입만 호출하고, 동기화는 SwiftData(+CloudKit)가 save 이후 자동으로 처리합니다.
@MainActor
struct EntryRepository {
    let context: ModelContext

    /// 특정 날짜의 기록 (보통 0~1개. 두 기기에서 동시에 처음 쓰면 잠깐 2개일 수 있음)
    func entries(on day: Date) throws -> [GratitudeEntry] {
        let start = Calendar.current.startOfDay(for: day)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let descriptor = FetchDescriptor<GratitudeEntry>(
            predicate: #Predicate { $0.createdAt >= start && $0.createdAt < end },
            sortBy: [SortDescriptor(\.updatedAt)]
        )
        return try context.fetch(descriptor)
    }

    /// 그 날짜의 감사일기를 저장합니다. 없으면 만들고, 있으면 Draft 내용으로 덮어씁니다.
    /// (Draft는 그 날의 기존 항목을 이미 포함하고 있음) 같은 날 기록이 여러 개면 하나로 합칩니다.
    @discardableResult
    func save(_ draft: EntryDraft) throws -> GratitudeEntry {
        let sameDay = try entries(on: draft.day)
        let entry: GratitudeEntry
        if let first = sameDay.first {
            entry = first
            sameDay.dropFirst().forEach { context.delete($0) }
        } else {
            entry = GratitudeEntry(day: draft.day, items: [], emotionLevel: draft.emotion.rawValue)
            context.insert(entry)
        }
        entry.createdAt = GratitudeEntry.normalizedDate(for: draft.day)
        entry.items = draft.cleanedItems
        entry.emotionLevel = draft.emotionChosen ? draft.emotion.rawValue : GratitudeEntry.unsetEmotion
        entry.summary = Optional(draft.summary).normalizedOptional
        entry.updatedAt = .now
        try context.save()          // 명시적 save → (켜져 있으면) CloudKit 업로드 예약
        CloudSyncService.shared.didChange(day: draft.day)    // (로그인돼 있으면) 서버에 바로 업로드
        return entry
    }

    func deleteEntries(on day: Date) throws {
        try entries(on: day).forEach { context.delete($0) }
        try context.save()
        CloudSyncService.shared.didChange(day: day)
    }
}
