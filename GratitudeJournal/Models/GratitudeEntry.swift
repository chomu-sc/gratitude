import Foundation
import SwiftData

/// 하루치 감사일기.
///
/// - **하루에 한 편**: 같은 날짜에 다시 쓰면 그 날 기록에 이어서 적습니다.
/// - `createdAt`은 '이 일기가 속한 날짜'입니다. 시간은 쓰지 않으므로 그날 정오(12:00)로 고정해
///   시간대가 바뀌어도 날짜가 하루 밀리지 않게 합니다. 실제 저장 시각은 `updatedAt`.
/// - 감사한 일 목록은 `gratitudeBody`에 한 줄에 하나씩(줄바꿈 구분) 저장하고 `items`로 다룹니다.
///   → 기존 스키마를 그대로 쓰므로 마이그레이션이 필요 없습니다.
///
/// ⚠️ SwiftData + CloudKit 동기화 제약
/// - 모든 저장 속성은 기본값이 있거나 옵셔널이어야 합니다.
/// - `@Attribute(.unique)`는 CloudKit과 함께 쓸 수 없습니다. → 같은 날 중복은 저장 시 하나로 합칩니다.
@Model
final class GratitudeEntry {
    /// 고유 식별자
    var id: UUID = UUID()
    /// 일기 날짜 (정오로 정규화)
    var createdAt: Date = Date()
    /// 마지막 저장 시각
    var updatedAt: Date = Date()
    /// 1(아주 불쾌함) ~ 7(아주 기분 좋음), 0 = 아직 고르지 않음 (작성 도중 닫아 자동 저장된 경우)
    var emotionLevel: Int = 4
    /// 감사한 일들 (한 줄에 하나)
    var gratitudeBody: String = ""
    /// 한 줄 총평 (선택 사항)
    var summary: String?

    init(
        id: UUID = UUID(),
        day: Date,
        items: [String],
        emotionLevel: Int,
        summary: String? = nil
    ) {
        self.id = id
        self.createdAt = GratitudeEntry.normalizedDate(for: day)
        self.updatedAt = .now
        self.emotionLevel = EmotionLevel.clamped(emotionLevel).rawValue
        self.gratitudeBody = GratitudeEntry.join(items)
        self.summary = summary.normalizedOptional
    }
}

extension GratitudeEntry {
    static let unsetEmotion = 0

    /// 기분을 골랐으면 그 단계, 아직이면 nil
    var recordedEmotion: EmotionLevel? {
        emotionLevel == Self.unsetEmotion ? nil : EmotionLevel.clamped(emotionLevel)
    }

    /// 캘린더 키로 쓰는 날짜 (해당 날짜의 00:00)
    var day: Date { Calendar.current.startOfDay(for: createdAt) }

    /// 감사한 일 목록
    var items: [String] {
        get {
            gratitudeBody
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set { gratitudeBody = GratitudeEntry.join(newValue) }
    }

    /// 목록에 보여줄 미리보기 문구: 총평이 있으면 총평, 없으면 첫 번째 감사한 일
    var previewText: String { summary ?? items.first ?? "" }

    /// 날짜만 의미가 있으므로 그날 정오로 고정
    static func normalizedDate(for day: Date) -> Date {
        let start = Calendar.current.startOfDay(for: day)
        return Calendar.current.date(byAdding: .hour, value: 12, to: start) ?? start
    }

    fileprivate static func join(_ items: [String]) -> String {
        items
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

extension Optional where Wrapped == String {
    /// 공백만 있는 문자열은 nil로 정규화
    var normalizedOptional: String? {
        guard let trimmed = self?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
