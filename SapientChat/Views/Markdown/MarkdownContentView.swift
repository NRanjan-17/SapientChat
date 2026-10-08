// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// A reply rendered with its structure: paragraphs, headings, lists,
/// quotes and code blocks.
struct MarkdownContentView: View {
    let text: String

    var body: some View {
        let blocks = MarkdownParser.blocks(from: text)
        VStack(alignment: .leading, spacing: 10) {
            // Blocks only ever grow at the end while a reply streams, so
            // position is a stable identity here.
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block)
            }
        }
    }
}

#Preview {
    ScrollView {
        MarkdownContentView(text: """
        ## Swap two numbers
        Here is a **Swift** function:

        ```swift
        func swap(_ a: inout Int, _ b: inout Int) {
            (a, b) = (b, a)
        }
        ```

        1. It takes both values `inout`.
        2. A tuple assignment swaps them.

        > No temporary variable needed.
        """)
        .padding()
    }
}
