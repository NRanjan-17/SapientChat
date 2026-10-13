// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// A quiet wash of SAPIENT blue behind a page. Liquid Glass shows what is
/// behind it, and behind a flat grey there is nothing to show; this gives
/// the glass surfaces (the composer, the home cards) colour to pick up,
/// most of all in a large Mac or iPad window.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    static let brand = Color(red: 0x2A / 255, green: 0x7D / 255, blue: 1)

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground)
            if !reduceTransparency {
                GeometryReader { proxy in
                    let size = max(proxy.size.width, proxy.size.height)
                    ZStack {
                        glow(Self.brand, opacity: colorScheme == .dark ? 0.34 : 0.22)
                            .frame(width: size * 0.9, height: size * 0.9)
                            .position(x: proxy.size.width * 0.18, y: proxy.size.height * 0.05)
                        glow(.cyan, opacity: colorScheme == .dark ? 0.20 : 0.14)
                            .frame(width: size * 0.7, height: size * 0.7)
                            .position(x: proxy.size.width * 0.95, y: proxy.size.height * 0.3)
                        glow(.indigo, opacity: colorScheme == .dark ? 0.26 : 0.12)
                            .frame(width: size * 0.8, height: size * 0.8)
                            .position(x: proxy.size.width * 0.6, y: proxy.size.height * 1.05)
                    }
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func glow(_ color: Color, opacity: Double) -> some View {
        Circle().fill(
            RadialGradient(colors: [color.opacity(opacity), color.opacity(0)], center: .center, startRadius: 0, endRadius: 400)
        )
    }
}

extension View {
    /// A Liquid Glass surface in `shape`; `interactive` makes it respond to
    /// touch and the pointer, for things you tap.
    func glassSurface(in shape: some Shape, interactive: Bool = false) -> some View {
        glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
    }
}

#Preview {
    AmbientBackground()
}
