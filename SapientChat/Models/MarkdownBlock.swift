// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// One block of a reply: the structure Markdown gives text (code, lists,
/// headings, quotes), which inline-only rendering used to flatten.
nonisolated enum MarkdownBlock: Equatable, Sendable {
    case paragraph(String)
    case heading(level: Int, text: String)
    /// `isClosed` is false while a reply is still streaming inside the fence.
    case code(language: String?, code: String, isClosed: Bool)
    case list(ordered: Bool, start: Int, items: [String])
    case quote(String)
}
