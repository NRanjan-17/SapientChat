// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Testing
@testable import SapientChat

struct MarkdownParserTests {
    @Test func codeBlocksKeepTheirLinesAndLanguage() {
        let blocks = MarkdownParser.blocks(from: """
        Here you go:

        ```swift
        func f() {
            print("hi")
        }
        ```
        Done.
        """)
        #expect(blocks == [
            .paragraph("Here you go:"),
            .code(language: "swift", code: "func f() {\n    print(\"hi\")\n}", isClosed: true),
            .paragraph("Done."),
        ])
    }

    @Test func anUnclosedFenceWhileStreamingIsStillCode() {
        let blocks = MarkdownParser.blocks(from: "Start\n```python\nx = 1\nprint(x")
        #expect(blocks == [.paragraph("Start"), .code(language: "python", code: "x = 1\nprint(x", isClosed: false)])
    }

    @Test func markdownInsideCodeIsNotInterpreted() {
        let blocks = MarkdownParser.blocks(from: "```\n# not a heading\n- not a list\n```")
        #expect(blocks == [.code(language: nil, code: "# not a heading\n- not a list", isClosed: true)])
    }

    @Test func listsHeadingsAndQuotes() {
        let blocks = MarkdownParser.blocks(from: """
        ## Steps
        1. Open the app
        2. Pick a model
           with enough memory
        - a bullet
        > A quote
        > continues
        """)
        #expect(blocks == [
            .heading(level: 2, text: "Steps"),
            .list(ordered: true, start: 1, items: ["Open the app", "Pick a model with enough memory"]),
            .list(ordered: false, start: 1, items: ["a bullet"]),
            .quote("A quote\ncontinues"),
        ])
    }

    @Test func numberedListsKeepTheirStartAndParagraphsKeepLineBreaks() {
        #expect(MarkdownParser.blocks(from: "3) third\n4) fourth") == [.list(ordered: true, start: 3, items: ["third", "fourth"])])
        #expect(MarkdownParser.blocks(from: "line one\nline two") == [.paragraph("line one\nline two")])
    }

    @Test func notQuiteMarkdownStaysText() {
        #expect(MarkdownParser.blocks(from: "#hashtag") == [.paragraph("#hashtag")])
        #expect(MarkdownParser.blocks(from: "2024 was good") == [.paragraph("2024 was good")])
        #expect(MarkdownParser.blocks(from: "") == [])
    }
}
