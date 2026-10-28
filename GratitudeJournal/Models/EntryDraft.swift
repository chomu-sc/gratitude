import Foundation

/// 작성 중인 감사한 일 한 개
struct DraftItem: Identifiable, Equatable {
    var id = UUID()
    var text: String
    /// 아직 저장되지 않은 새 항목인지. 날짜를 바꾸면 새 항목만 새 날짜로 따라갑니다.
    var isNew: Bool
}

/// 편집 중인 값. 모델에 바로 바인딩하지 않고 저장(또는 닫을 때 자동 저장) 시점에만 커밋합니다.
struct EntryDraft: Equatable {
    /// 변경 여부 비교용 요약
    struct Snapshot: Equatable {
        var items: [String] = []
        var emotion: EmotionLevel?
        var summary: String?
    }

    var day: Date
    var items: [DraftItem] = []
    var emotion: EmotionLevel = .neutral
    /// 기분을 실제로 골랐는지 (기분 화면까지 가지 않고 닫으면 false → '기분 미기록'으로 저장)
    var emotionChosen = false
    var summary: String = ""
    /// 선택한 날짜에 이미 기록이 있어 이어서 쓰는 중인지
    private(set) var isExistingDay = false
    /// 마지막으로 불러오거나 저장한 상태
    private(set) var savedSnapshot = Snapshot()

    init(day: Date = .now) {
        self.day = Calendar.current.startOfDay(for: day)
    }

    var cleanedItems: [String] {
        items
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var canSave: Bool { !cleanedItems.isEmpty }
    var hasNewItems: Bool { items.contains { $0.isNew } }

    var snapshot: Snapshot {
        Snapshot(items: cleanedItems,
                 emotion: emotionChosen ? emotion : nil,
                 summary: Optional(summary).normalizedOptional)
    }

    /// 저장되지 않은 변경이 있는지
    var hasChanges: Bool { snapshot != savedSnapshot }

    mutating func markSaved() {
        savedSnapshot = snapshot
        for index in items.indices { items[index].isNew = false }
        isExistingDay = true
    }

    /// 날짜 선택/변경 시 호출: 그 날짜의 기존 기록을 불러오고, 아직 저장 안 된 새 항목은 유지합니다.
    mutating func load(day newDay: Date, existing: [GratitudeEntry]) {
        let carried = items.filter { $0.isNew }
        let loadedItems = existing.flatMap { $0.items }
        day = Calendar.current.startOfDay(for: newDay)

        if let first = existing.first {
            emotion = first.recordedEmotion ?? .neutral
            emotionChosen = first.recordedEmotion != nil
            summary = first.summary ?? ""
        } else {
            // 빈 날로 옮기면 이전 날의 기분/총평을 끌고 가지 않음
            emotion = .neutral
            emotionChosen = false
            summary = ""
        }

        items = loadedItems.map { DraftItem(text: $0, isNew: false) }
        savedSnapshot = existing.isEmpty ? Snapshot() : snapshot
        items += carried
        isExistingDay = !existing.isEmpty
    }
}
