// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

extension View {
    /// A large page title at the top left on wide screens (iPad, Mac). There
    /// the navigation bar's row is shared with the tab bar and draws no
    /// title at all, so each tab's page says what it is itself. On iPhone
    /// the navigation bar shows the title and this adds nothing.
    ///
    /// - Parameter columnWidth: the page's readable column, when it has one
    ///   (see `readableContentWidth`), so the title lines up with it.
    func pageTitle(_ title: String, columnWidth: CGFloat? = nil) -> some View {
        modifier(PageTitle(title: title, columnWidth: columnWidth))
    }
}

private struct PageTitle: ViewModifier {
    let title: String
    let columnWidth: CGFloat?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var width: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .top, spacing: 0) {
                if horizontalSizeClass == .regular {
                    Text(title)
                        .font(.largeTitle.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, leading)
                        .padding(.trailing, 20)
                        .padding(.bottom, 4)
                        // Solid up to the top of the screen, so a page
                        // scrolled up doesn't show through the title or
                        // the tab bar above it.
                        .background(Color(.systemGroupedBackground).ignoresSafeArea(edges: .top))
                        .accessibilityAddTraits(.isHeader)
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    /// The column's own margin plus a row's inset, or the page edge.
    private var leading: CGFloat {
        guard let columnWidth, width > columnWidth else { return 20 }
        return max(20, (width - columnWidth) / 2) + 20
    }
}
