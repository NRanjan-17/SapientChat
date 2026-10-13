// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Narrows the request log: by text, to failures, or to one calling app.
nonisolated struct RequestLogFilter: Equatable, Sendable {
    /// Matched against the path, model, app, prompt, reply and error.
    var text = ""
    /// Only requests answered with a 4xx or 5xx status.
    var errorsOnly = false
    /// Only requests from this app; nil is every app.
    var source: String?

    var isActive: Bool { errorsOnly || source != nil }

    func apply(_ entries: [RequestLogEntry]) -> [RequestLogEntry] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return entries.filter { entry in
            if errorsOnly && entry.status < 400 { return false }
            if let source, entry.source != source { return false }
            guard !query.isEmpty else { return true }
            let fields = [entry.path, entry.model, entry.source, entry.promptPreview, entry.reply, entry.error, String(entry.status)]
            return fields.contains { $0?.localizedStandardContains(query) == true }
        }
    }

    /// The apps named in `entries`, in alphabetical order.
    static func sources(in entries: [RequestLogEntry]) -> [String] {
        Set(entries.compactMap(\.source)).sorted()
    }

    /// `entries` as a JSON array, for sharing or attaching to a bug report.
    static func export(_ entries: [RequestLogEntry]) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return (try? encoder.encode(entries)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }
}

extension RequestLogEntry {
    /// Whether it can be opened in the Playground and sent again: a GET, or
    /// a request whose body was saved.
    var canReplay: Bool {
        method == "GET" || requestBody != nil
    }
}
