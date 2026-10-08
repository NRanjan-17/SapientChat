// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Follows one piece of work (an API request or a benchmark) and keeps its
/// Live Activity current. Starts the activity once the model is known,
/// sends phase changes at once and token counts at most about once a
/// second (iOS rate-limits Live Activity updates), and ends it with the
/// final stats.
final class LiveActivityTracker {
    typealias State = SapientActivityAttributes.ContentState

    private let service: any LiveActivityService
    private let title: String
    private let clock: () -> Date
    private let minimumInterval: TimeInterval
    private var id: UUID?
    private(set) var state: State
    private var lastSent = Date.distantPast
    private var generationStart: Date?
    private var firstToken: Date?
    private var isOver = false

    init(
        service: any LiveActivityService,
        title: String,
        minimumInterval: TimeInterval = 1,
        clock: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.title = title
        self.clock = clock
        self.minimumInterval = minimumInterval
        state = State(phase: .preparing, startedAt: clock())
    }

    /// Starts the activity for `model`; later calls do nothing.
    func start(model: String) {
        guard id == nil, !isOver else { return }
        id = service.start(SapientActivityAttributes(title: title, model: model), state: state)
        lastSent = clock()
    }

    func phase(_ phase: ModelPhase) {
        switch phase {
        case .downloading(let progress):
            state.phase = .downloading
            state.progress = progress.fraction
            state.detail = progress.totalBytes > 0
                ? "\(Format.bytes(progress.downloadedBytes)) of \(Format.bytes(progress.totalBytes))"
                : nil
            send(force: state.progress == nil)
        case .loading:
            state.phase = .loading
            state.progress = nil
            state.detail = nil
            send(force: true)
        }
    }

    /// Marks the start of generation; time to first token counts from here.
    func generating() {
        generationStart = clock()
        state.phase = .generating
        state.progress = nil
        state.detail = nil
        send(force: true)
    }

    /// One more streamed fragment (≈ one token).
    func token() {
        let now = clock()
        if firstToken == nil {
            firstToken = now
            if let start = generationStart {
                state.timeToFirstTokenMs = Int((now.timeIntervalSince(start) * 1000).rounded())
            }
        }
        state.tokens += 1
        if let first = firstToken, state.tokens > 1 {
            let seconds = now.timeIntervalSince(first)
            if seconds > 0 { state.tokensPerSecond = Double(state.tokens - 1) / seconds }
        }
        send(force: state.tokens == 1)
    }

    /// A benchmark run finished: `completed` of `total`, with its stats.
    func benchmark(completed: Int, total: Int, lastRun: BenchmarkRunResult?) {
        state.phase = .benchmarking
        state.progress = total > 0 ? Double(completed) / Double(total) : nil
        state.detail = "Run \(min(completed + 1, total)) of \(total)"
        if let run = lastRun {
            state.tokens = run.tokens
            state.tokensPerSecond = run.decodeTokensPerSecond
            state.timeToFirstTokenMs = Int(run.ttftMs)
        }
        send(force: true)
    }

    func finish(detail: String? = nil, tokensPerSecond: Double? = nil, timeToFirstTokenMs: Int? = nil) {
        guard !isOver else { return }
        isOver = true
        state.phase = .finished
        state.progress = nil
        state.detail = detail
        if let tokensPerSecond { state.tokensPerSecond = tokensPerSecond }
        if let timeToFirstTokenMs { state.timeToFirstTokenMs = timeToFirstTokenMs }
        state.endedAt = clock()
        if let id { service.end(id, state: state) }
    }

    func fail(_ message: String) {
        guard !isOver else { return }
        isOver = true
        state.phase = .failed
        state.progress = nil
        state.detail = message
        state.endedAt = clock()
        if let id { service.end(id, state: state) }
    }

    private func send(force: Bool) {
        guard let id, !isOver else { return }
        let now = clock()
        guard force || now.timeIntervalSince(lastSent) >= minimumInterval else { return }
        lastSent = now
        service.update(id, state: state)
    }
}
