// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Splits Markdown into blocks, line by line. Small and forgiving on
/// purpose: replies stream in, so a half-written block (an unclosed code
/// fence, a list still growing) must render sensibly at every token.
/// Inline syntax (bold, `code`, links) stays inside the block text and is
/// rendered by `AttributedString(markdown:)`.
nonisolated enum MarkdownParser {
    static func blocks(from text: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var list: (ordered: Bool, start: Int, items: [String])?
        var fence: (marker: String, language: String?, lines: [String])?

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
            if !quote.isEmpty {
                blocks.append(.quote(quote.joined(separator: "\n")))
                quote.removeAll()
            }
            if let current = list {
                blocks.append(.list(ordered: current.ordered, start: current.start, items: current.items))
                list = nil
            }
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if let open = fence {
                let markerCharacter = open.marker.first ?? "`"
                if line.count >= open.marker.count && line.allSatisfy({ $0 == markerCharacter }) {
                    blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n"), isClosed: true))
                    fence = nil
                } else {
                    fence?.lines.append(rawLine)
                }
                continue
            }

            if let marker = fenceMarker(line) {
                flush()
                let language = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
                fence = (marker, language.isEmpty ? nil : language, [])
                continue
            }

            if line.isEmpty {
                flush()
                continue
            }

            if let (level, title) = heading(line) {
                flush()
                blocks.append(.heading(level: level, text: title))
                continue
            }

            if line.hasPrefix(">") {
                if quote.isEmpty { flush() }
                quote.append(String(line.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            if let item = listItem(line) {
                if let current = list, current.ordered == item.ordered {
                    list?.items.append(item.text)
                } else {
                    flush()
                    list = (item.ordered, item.number ?? 1, [item.text])
                }
                continue
            }

            if var current = list, let last = current.items.indices.last, rawLine.first == " " || rawLine.first == "\t" {
                // An indented line continues the last list item.
                current.items[last] += " " + line
                list = current
                continue
            }

            if !quote.isEmpty || list != nil { flush() }
            paragraph.append(rawLine)
        }

        if let open = fence {
            blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n"), isClosed: false))
        }
        flush()
        return blocks
    }

    /// "```" or "~~~" (three or more) at the start of a line.
    private static func fenceMarker(_ line: String) -> String? {
        for character in ["`", "~"] {
            let run = line.prefix { String($0) == character }
            if run.count >= 3 { return String(run) }
        }
        return nil
    }

    /// "## Title" → (2, "Title").
    private static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }
        guard (1...6).contains(hashes.count), line.dropFirst(hashes.count).first == " " else { return nil }
        return (hashes.count, line.dropFirst(hashes.count + 1).trimmingCharacters(in: .whitespaces))
    }

    /// "- item", "* item", "+ item", "3. item", "3) item".
    private static func listItem(_ line: String) -> (ordered: Bool, number: Int?, text: String)? {
        if let first = line.first, "-*+".contains(first), line.dropFirst().first == " " {
            return (false, nil, String(line.dropFirst(2)))
        }
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 9 else { return nil }
        let rest = line.dropFirst(digits.count)
        guard let mark = rest.first, mark == "." || mark == ")", rest.dropFirst().first == " " else { return nil }
        return (true, Int(digits), String(rest.dropFirst(2)))
    }
}
