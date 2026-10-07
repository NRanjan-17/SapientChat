import SwiftUI

extension View {
    /// Keeps a scrolling view's content in a centred column of at most
    /// `maxWidth` on wide screens (iPad, large windows); on iPhone the
    /// margin is zero, so nothing changes. The scroll view itself stays full
    /// width, so its background and scroll indicators reach the edges.
    func readableContentWidth(_ maxWidth: CGFloat = 720) -> some View {
        modifier(ReadableContentMargins(maxWidth: maxWidth))
    }
}

private struct ReadableContentMargins: ViewModifier {
    let maxWidth: CGFloat
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, max(0, (width - maxWidth) / 2), for: .scrollContent)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
