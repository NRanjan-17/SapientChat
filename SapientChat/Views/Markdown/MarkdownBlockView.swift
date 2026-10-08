// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// One Markdown block.
struct MarkdownBlockView: View {
    let block: MarkdownBlock

    var body: some View {
        switch block {
        case .paragraph(let text):
            Text(InlineMarkdown.attributed(text))
        case .heading(let level, let text):
            Text(InlineMarkdown.attributed(text))
                .font(level <= 1 ? .title3.bold() : level == 2 ? .headline : .subheadline.bold())
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
        case .code(let language, let code, _):
            CodeBlockView(language: language, code: code)
        case .list(let ordered, let start, let items):
            MarkdownListView(ordered: ordered, start: start, items: items)
        case .quote(let text):
            Text(InlineMarkdown.attributed(text))
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Capsule().fill(.tertiary).frame(width: 3)
                }
        }
    }
}
