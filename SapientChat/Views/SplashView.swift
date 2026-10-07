import SwiftUI

/// Shown over the app as it opens: the SAPIENT mark's three strokes pop
/// in, "SAPIENT" fades in, then it all lifts away. It starts on the launch
/// screen's colour (`LaunchBackground`), so the hand-off has no jump. The
/// app loads underneath, so this never delays it. Reduce Motion: a fade.
struct SplashView: View {
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var shownStrokes = 0
    @State private var showsWordmark = false
    @State private var isLeaving = false

    var body: some View {
        ZStack {
            Color(.launchBackground)
                .ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    ForEach(SapientMarkShape.strokes.indices, id: \.self) { index in
                        SapientMarkShape(stroke: index)
                            .fill(markColor)
                            .scaleEffect(shownStrokes > index ? 1 : 0.4)
                            .opacity(shownStrokes > index ? 1 : 0)
                    }
                }
                .frame(width: 112, height: 112)
                Text("SAPIENT")
                    .font(.title3.weight(.semibold))
                    .tracking(6)
                    .foregroundStyle(.white)
                    .opacity(showsWordmark ? 1 : 0)
                    .offset(y: showsWordmark ? 0 : 8)
            }
            .scaleEffect(isLeaving && !reduceMotion ? 1.12 : 1)
        }
        .opacity(isLeaving ? 0 : 1)
        .accessibilityHidden(true)
        .task { await play() }
    }

    /// White on SAPIENT blue; SAPIENT blue on near-black, like the icon.
    private var markColor: Color {
        colorScheme == .dark ? Color(red: 0x2A / 255, green: 0x7D / 255, blue: 1) : .white
    }

    private func play() async {
        if reduceMotion {
            shownStrokes = SapientMarkShape.strokes.count
            showsWordmark = true
            try? await Task.sleep(for: .milliseconds(500))
        } else {
            for stroke in SapientMarkShape.strokes.indices {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.62)) { shownStrokes = stroke + 1 }
                try? await Task.sleep(for: .milliseconds(130))
            }
            withAnimation(.easeOut(duration: 0.35)) { showsWordmark = true }
            try? await Task.sleep(for: .milliseconds(550))
        }
        withAnimation(.easeIn(duration: 0.3)) { isLeaving = true }
        try? await Task.sleep(for: .milliseconds(300))
        onFinish()
    }
}

/// One stroke of the SAPIENT mark (the same polygons as the app icon),
/// scaled into the shape's square.
struct SapientMarkShape: Shape {
    /// Corner points in the icon's 1024 space; the mark spans 182…842 x 186…846.
    static let strokes: [[CGPoint]] = [
        [CGPoint(x: 360.3, y: 202.9), CGPoint(x: 447.5, y: 202.9), CGPoint(x: 733.9, y: 671.3), CGPoint(x: 650.4, y: 671.3)],
        [CGPoint(x: 259.8, y: 502.5), CGPoint(x: 805.9, y: 455.1), CGPoint(x: 805.9, y: 531.0), CGPoint(x: 218.1, y: 578.4)],
        [CGPoint(x: 337.5, y: 745.2), CGPoint(x: 694.0, y: 326.2), CGPoint(x: 720.6, y: 405.8), CGPoint(x: 366.0, y: 828.7)],
    ]
    private static let origin = CGPoint(x: 182, y: 186)
    private static let span: CGFloat = 660

    let stroke: Int

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let points = Self.strokes[stroke].map { point in
            CGPoint(
                x: rect.midX - side / 2 + (point.x - Self.origin.x) / Self.span * side,
                y: rect.midY - side / 2 + (point.y - Self.origin.y) / Self.span * side
            )
        }
        var path = Path()
        path.addLines(points)
        path.closeSubpath()
        return path
    }
}

#Preview {
    SplashView {}
}
