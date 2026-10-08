// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Collects one request's log entry while the router works on it: the
/// model, the prompt, the streamed reply and its timing. Finished once the
/// whole response has gone out, so a streamed reply is saved complete.
final class RequestCapture {
    private(set) var entry: RequestLogEntry
    private let started = ContinuousClock.now
    private var generationStarted: ContinuousClock.Instant?
    private var firstToken: ContinuousClock.Instant?
    private var lastToken: ContinuousClock.Instant?
    private var isFinished = false

    init(_ request: HTTPRequest, source: String?) {
        entry = RequestLogEntry(
            date: .now, method: request.method, path: request.path, source: source,
            requestBody: RequestLogEntry.text(of: request.body)
        )
    }

    func model(_ alias: String) {
        entry.model = alias
    }

    func prompt(_ history: [ChatMessage]) {
        entry.messages = history.map { RequestLogEntry.Message(role: $0.role.rawValue, text: $0.text) }
    }

    func generating() {
        generationStarted = .now
        entry.reply = ""
        entry.tokens = 0
    }

    /// One streamed fragment (≈ one token) and the text it added after stop filtering.
    func token(_ text: String) {
        let now = ContinuousClock.now
        if firstToken == nil {
            firstToken = now
            if let generationStarted { entry.timeToFirstTokenMs = (now - generationStarted).milliseconds }
        }
        lastToken = now
        entry.tokens = (entry.tokens ?? 0) + 1
        entry.reply = (entry.reply ?? "") + text
    }

    /// Text the stop filter released after the last fragment.
    func append(_ text: String) {
        entry.reply = (entry.reply ?? "") + text
    }

    func failed(_ message: String) {
        entry.error = message
    }

    /// The final entry; later calls return nil.
    func finish(status: Int, responseBody: Data?) -> RequestLogEntry? {
        guard !isFinished else { return nil }
        isFinished = true
        entry.status = status
        if let responseBody { entry.responseBody = RequestLogEntry.text(of: responseBody) }
        entry.durationMs = (ContinuousClock.now - started).milliseconds
        if status >= 400, entry.error == nil, let responseBody,
           let body = try? APIJSON.decoder.decode(ServeErrorBody.self, from: responseBody) {
            entry.error = body.error.message
        }
        if let first = firstToken, let last = lastToken, let tokens = entry.tokens, tokens > 1 {
            let seconds = Double((last - first).milliseconds) / 1000
            if seconds > 0 { entry.tokensPerSecond = Double(tokens - 1) / seconds }
        }
        return entry
    }
}
