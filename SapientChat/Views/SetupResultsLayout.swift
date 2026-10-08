// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Benchmark and Compare: on wide screens, setup in a column on the left
/// and progress and results on the right, so a run's numbers are visible
/// while it goes; one form otherwise (iPhone, iPad portrait in a narrow
/// window). Both closures supply form sections.
struct SetupResultsLayout<Setup: View, Results: View>: View {
    @ViewBuilder let setup: () -> Setup
    @ViewBuilder let results: () -> Results
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            HStack(spacing: 0) {
                Form { setup() }
                    .scrollDismissesKeyboard(.interactively)
                    .frame(width: 420)
                Divider()
                Form { results() }
                    .scrollDismissesKeyboard(.interactively)
                    .readableContentWidth(820)
            }
        } else {
            Form {
                setup()
                results()
            }
            .scrollDismissesKeyboard(.interactively)
            .readableContentWidth(720)
        }
    }
}
