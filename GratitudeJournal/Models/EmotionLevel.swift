import SwiftUI

/// 7단계 감정. 저장은 `Int`(1~7)로 하고, 코드에서는 이 enum으로 다룹니다.
enum EmotionLevel: Int, CaseIterable, Identifiable, Codable, Sendable {
    case veryUnpleasant = 1
    case unpleasant
    case slightlyUnpleasant
    case neutral
    case slightlyPleasant
    case pleasant
    case veryPleasant

    var id: Int { rawValue }

    static func clamped(_ value: Int) -> EmotionLevel {
        EmotionLevel(rawValue: min(max(value, 1), 7)) ?? .neutral
    }

    /// 0.0(아주 불쾌함) ~ 1.0(아주 기분 좋음) 사이의 위치값으로 변환
    static func from(progress: Double) -> EmotionLevel {
        clamped(Int((min(max(progress, 0), 1) * 6).rounded()) + 1)
    }

    var label: String {
        switch self {
        case .veryUnpleasant:     "아주 불쾌함"
        case .unpleasant:         "불쾌함"
        case .slightlyUnpleasant: "약간 불쾌함"
        case .neutral:            "보통"
        case .slightlyPleasant:   "약간 기분 좋음"
        case .pleasant:           "기분 좋음"
        case .veryPleasant:       "아주 기분 좋음"
        }
    }

    /// 애플 '마음 상태' 기록처럼 보라(불쾌) → 하늘 → 초록 → 노랑/주황(기분 좋음)으로 이어지는 색
    var color: Color {
        switch self {
        case .veryUnpleasant:     Color(red: 0.42, green: 0.36, blue: 0.84)
        case .unpleasant:         Color(red: 0.36, green: 0.48, blue: 0.88)
        case .slightlyUnpleasant: Color(red: 0.31, green: 0.64, blue: 0.85)
        case .neutral:            Color(red: 0.36, green: 0.76, blue: 0.71)
        case .slightlyPleasant:   Color(red: 0.66, green: 0.83, blue: 0.44)
        case .pleasant:           Color(red: 0.97, green: 0.78, blue: 0.27)
        case .veryPleasant:       Color(red: 1.00, green: 0.66, blue: 0.13)
        }
    }

    /// 0.0 ~ 1.0
    var normalized: Double { Double(rawValue - 1) / 6 }

    /// 얼굴 입 모양: -1(찡그림) ~ 1(활짝 웃음)
    var mouthCurvature: Double { normalized * 2 - 1 }

    var next: EmotionLevel { .clamped(rawValue + 1) }
    var previous: EmotionLevel { .clamped(rawValue - 1) }
}
