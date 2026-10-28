import SwiftUI

/// 7단계 감정 슬라이더 (애플 일기/건강 앱 '마음 상태' 기록 UI 스타일)
///
/// - 드래그 중에는 손가락을 연속적으로 따라가고, 놓으면 가장 가까운 단계로 스냅
/// - 단계가 바뀔 때마다 햅틱(iOS) / 트랙패드 피드백(macOS)
/// - VoiceOver: 위/아래 스와이프로 조절, macOS: ← → 키로 조절
struct EmotionSlider: View {
    @Binding var level: EmotionLevel
    var compact: Bool = false

    /// 드래그 중의 연속 위치(0~1). nil이면 현재 단계 위치를 사용.
    @State private var dragProgress: Double?

    private var thumbSize: CGFloat { compact ? 24 : 30 }

    var body: some View {
        VStack(spacing: compact ? 10 : 18) {
            if compact {
                HStack(spacing: 12) {
                    MoodFace(level: level).frame(width: 40)
                    label
                    Spacer()
                }
            } else {
                MoodFace(level: level).frame(width: 112)
                label
            }

            track

            HStack {
                Text(EmotionLevel.veryUnpleasant.label)
                Spacer()
                Text(EmotionLevel.veryPleasant.label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var label: some View {
        Text(level.label)
            .font(compact ? .headline : .title3.weight(.semibold))
            .foregroundStyle(.primary)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.15), value: level)
    }

    private var track: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - thumbSize, 1)
            let progress = dragProgress ?? level.normalized

            ZStack(alignment: .leading) {
                // 그라데이션 트랙
                Capsule()
                    .fill(LinearGradient(colors: EmotionLevel.allCases.map(\.color),
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: compact ? 8 : 10)
                    .padding(.horizontal, thumbSize / 2)

                // 7개 눈금
                ForEach(EmotionLevel.allCases) { step in
                    Circle()
                        .fill(.white.opacity(step == level ? 0 : 0.85))
                        .frame(width: 4, height: 4)
                        .offset(x: thumbSize / 2 + usable * step.normalized - 2)
                }

                // 손잡이
                Circle()
                    .fill(.white)
                    .overlay(Circle().fill(level.color).padding(compact ? 4 : 5))
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
                    .frame(width: thumbSize, height: thumbSize)
                    .scaleEffect(dragProgress == nil ? 1 : 1.12)
                    .offset(x: usable * progress)
            }
            .frame(height: thumbSize)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = min(max((value.location.x - thumbSize / 2) / usable, 0), 1)
                        dragProgress = p
                        let snapped = EmotionLevel.from(progress: p)
                        if snapped != level { level = snapped }
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragProgress = nil }
                    }
            )
        }
        .frame(height: 44)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: level)
        .sensoryFeedback(.selection, trigger: level)
        // 접근성
        .accessibilityElement()
        .accessibilityLabel("오늘의 기분")
        .accessibilityValue("7단계 중 \(level.rawValue)단계, \(level.label)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: level = level.next
            case .decrement: level = level.previous
            @unknown default: break
            }
        }
        // 키보드 (macOS / iPad 하드웨어 키보드)
        .focusable()
        .onKeyPress(.leftArrow)  { level = level.previous; return .handled }
        .onKeyPress(.rightArrow) { level = level.next; return .handled }
    }
}

#Preview {
    @Previewable @State var level: EmotionLevel = .neutral
    VStack(spacing: 40) {
        EmotionSlider(level: $level)
        EmotionSlider(level: $level, compact: true)
    }
    .padding(24)
}
