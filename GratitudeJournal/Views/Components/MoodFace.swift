import SwiftUI

/// 감정 단계에 따라 색과 입 모양이 부드럽게 변하는 얼굴. (앱 아이콘의 노란 스마일과 같은 디자인 언어)
struct MoodFace: View {
    var level: EmotionLevel

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                Circle()
                    .fill(level.color.gradient)
                    .shadow(color: level.color.opacity(0.45), radius: s * 0.12, y: s * 0.05)

                HStack(spacing: s * 0.22) {
                    Capsule().frame(width: s * 0.085, height: s * 0.15)
                    Capsule().frame(width: s * 0.085, height: s * 0.15)
                }
                .offset(y: -s * 0.1)

                MouthShape(curvature: level.mouthCurvature)
                    .stroke(style: StrokeStyle(lineWidth: s * 0.065, lineCap: .round))
                    .frame(width: s * 0.44, height: s * 0.2)
                    .offset(y: s * 0.17)
            }
            .foregroundStyle(.black.opacity(0.72))
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: level)
        .accessibilityHidden(true)
    }
}

/// curvature: -1(찡그림) ~ 0(일자) ~ 1(웃음). animatableData 덕분에 단계 사이가 자연스럽게 모핑됩니다.
struct MouthShape: Shape {
    var curvature: Double

    var animatableData: Double {
        get { curvature }
        set { curvature = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let y = rect.midY - rect.height * 0.5 * curvature
        path.move(to: CGPoint(x: rect.minX, y: y))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: y),
            control: CGPoint(x: rect.midX, y: y + rect.height * 2 * curvature)
        )
        return path
    }
}

#Preview {
    HStack {
        ForEach(EmotionLevel.allCases) { MoodFace(level: $0).frame(width: 44) }
    }
    .padding()
}
