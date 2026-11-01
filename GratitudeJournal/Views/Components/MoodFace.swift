import SwiftUI

/// 감정 단계에 따라 색과 표정이 부드럽게 변하는 얼굴 (iPhone 웹앱과 같은 디자인)
/// - 불쾌함: 입꼬리가 내려간 울상 + 시무룩한 눈썹
/// - 보통: 일자 입
/// - 기분 좋음: 자연스러운 미소 + 볼터치, 아주 기분 좋음은 웃는 눈과 살짝 벌린 입
struct MoodFace: View {
    var level: EmotionLevel

    private var curvature: Double { Double(level.rawValue - 4) / 3 }   // -1 ~ 1
    private let ink = Color.black.opacity(0.72)

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let u = s / 100          // 100 단위 좌표계
            ZStack {
                Circle()
                    .fill(level.color.gradient)
                    .shadow(color: level.color.opacity(0.45), radius: s * 0.12, y: s * 0.05)

                if level.rawValue >= 6 {
                    // 볼터치
                    HStack(spacing: 36 * u) {
                        Ellipse().frame(width: 14 * u, height: 9 * u)
                        Ellipse().frame(width: 14 * u, height: 9 * u)
                    }
                    .foregroundStyle(Color(red: 1, green: 0.48, blue: 0.42).opacity(level == .veryPleasant ? 0.35 : 0.25))
                    .offset(y: 8 * u)
                }

                if level.rawValue <= 2 {
                    BrowShape(tilt: level == .veryUnpleasant ? 6 : 3.5)
                        .stroke(ink.opacity(0.85), style: StrokeStyle(lineWidth: 4.5 * u, lineCap: .round))
                }

                if level == .veryPleasant {
                    HappyEyesShape()
                        .stroke(ink, style: StrokeStyle(lineWidth: 6 * u, lineCap: .round))
                } else {
                    HStack(spacing: 22 * u) {
                        Capsule().frame(width: 8.5 * u, height: 14 * u)
                        Capsule().frame(width: 8.5 * u, height: 14 * u)
                    }
                    .foregroundStyle(ink)
                    .offset(y: -10 * u)
                }

                if level == .veryPleasant {
                    MouthShape(curvature: curvature, open: true)
                        .fill(ink)
                    MouthShape(curvature: curvature, open: true)
                        .stroke(ink, style: StrokeStyle(lineWidth: 4 * u, lineJoin: .round))
                } else {
                    MouthShape(curvature: curvature)
                        .stroke(ink, style: StrokeStyle(lineWidth: 6 * u, lineCap: .round))
                }
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: level)
        .accessibilityHidden(true)
    }
}

/// 입. curvature -1(울상) ~ 0(일자) ~ 1(미소). 단계 사이가 자연스럽게 모핑됩니다.
/// 좌표는 얼굴 전체를 100×100으로 봤을 때 기준 (웹앱과 같은 수치)
struct MouthShape: Shape {
    var curvature: Double
    var open = false

    var animatableData: Double {
        get { curvature }
        set { curvature = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * u, oy = rect.midY - 50 * u
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * u, y: oy + y * u) }

        let c = curvature
        let half = 18 + 3 * abs(c)
        let yEnd = 67 - 6 * c
        let ctrl = 67 + 14 * c

        var path = Path()
        path.move(to: p(50 - half, yEnd))
        if open {
            path.addQuadCurve(to: p(50 + half, yEnd), control: p(50, yEnd + 3))
            path.addQuadCurve(to: p(50 - half, yEnd), control: p(50, ctrl + 7))
            path.closeSubpath()
        } else {
            path.addQuadCurve(to: p(50 + half, yEnd), control: p(50, ctrl))
        }
        return path
    }
}

/// 웃는 눈 (︶ ︶ 를 뒤집은 모양)
private struct HappyEyesShape: Shape {
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * u, oy = rect.midY - 50 * u
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * u, y: oy + y * u) }
        var path = Path()
        path.move(to: p(28.5, 43)); path.addQuadCurve(to: p(41, 43), control: p(34.75, 34))
        path.move(to: p(59, 43)); path.addQuadCurve(to: p(71.5, 43), control: p(65.25, 34))
        return path
    }
}

/// 시무룩한 눈썹 (안쪽 끝이 올라감)
private struct BrowShape: Shape {
    var tilt: Double
    func path(in rect: CGRect) -> Path {
        let u = min(rect.width, rect.height) / 100
        let ox = rect.midX - 50 * u, oy = rect.midY - 50 * u
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: ox + x * u, y: oy + y * u) }
        var path = Path()
        path.move(to: p(26, 26 + tilt / 2)); path.addLine(to: p(40, 26 - tilt / 2))
        path.move(to: p(60, 26 - tilt / 2)); path.addLine(to: p(74, 26 + tilt / 2))
        return path
    }
}

#Preview {
    HStack {
        ForEach(EmotionLevel.allCases) { MoodFace(level: $0).frame(width: 56) }
    }
    .padding()
}
