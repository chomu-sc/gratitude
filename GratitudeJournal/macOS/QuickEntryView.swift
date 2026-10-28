#if os(macOS)
import SwiftUI
import SwiftData

/// 빠른 작성 (⌘⇧G 플로팅 패널 · 메뉴 막대 공용)
/// 메인 앱과 같은 단계형 흐름(하나씩 적기 → 기분·총평)을 작은 크기로 보여줍니다.
struct QuickEntryView: View {
    var onDone: () -> Void = {}

    var body: some View {
        GratitudeFlowView(style: .compact) { _ in onDone() }
            .frame(height: 470)
    }
}
#endif
