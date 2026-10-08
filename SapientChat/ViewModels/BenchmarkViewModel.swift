// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// State and actions for the benchmark screen.
@Observable
final class BenchmarkViewModel: Identifiable {
    enum State: Equatable {
        case idle
        case running(BenchmarkProgress)
        case finished(BenchmarkResult)
        case failed(String)
    }

    let id = UUID()
    /// The model to measure; it runs on the shared engine (a model a chat
    /// already has loaded is reused, not loaded twice).
    var model: String
    /// Models to choose from; empty means the model is fixed.
    let availableModels: [PhoneModel]
    var settings = BenchmarkSettings()
    private(set) var state: State = .idle
    /// Runs finished so far in the current benchmark, shown as they come.
    private(set) var completedRuns: [BenchmarkRunResult] = []

    @ObservationIgnored private let service: any BenchmarkService
    /// Told whether the benchmark finished (true) or failed (false).
    @ObservationIgnored private let onFinish: (Bool) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let liveActivities: any LiveActivityService
    @ObservationIgnored private var activity: LiveActivityTracker?

    init(
        model: String,
        service: any BenchmarkService,
        availableModels: [PhoneModel] = [],
        state: State = .idle,
        liveActivities: any LiveActivityService = NoLiveActivities(),
        onFinish: @escaping (Bool) -> Void = { _ in }
    ) {
        self.liveActivities = liveActivities
        self.model = model
        self.availableModels = availableModels
        self.state = state
        self.service = service
        self.onFinish = onFinish
    }

    var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    var result: BenchmarkResult? {
        if case .finished(let result) = state { result } else { nil }
    }

    var canRun: Bool {
        !isRunning && settings.runs > 0 && settings.maxTokens > 0
            && !settings.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func run() {
        guard canRun else { return }
        let settings = settings
        state = .running(BenchmarkProgress(completed: 0, total: settings.totalRuns, lastRun: nil))
        completedRuns = []
        let activity = LiveActivityTracker(service: liveActivities, title: "Benchmark")
        activity.start(model: availableModels.first { $0.alias == model }?.displayName ?? model)
        activity.benchmark(completed: 0, total: settings.totalRuns, lastRun: nil)
        self.activity = activity
        task = Task { [weak self, service, model] in
            do {
                let result = try await service.benchmark(model: model, settings: settings) { progress in
                    Task { @MainActor in self?.progressed(progress) }
                }
                self?.finish(.finished(result))
            } catch {
                self?.finish(.failed(String(describing: error)))
            }
        }
    }

    /// Stops after the current run; the finished runs are still reported.
    func cancel() {
        task?.cancel()
    }

    private func progressed(_ progress: BenchmarkProgress) {
        // Progress hops arrive as separate tasks: never move backwards, and
        // never overwrite a finished state.
        guard case .running(let current) = state, progress.completed > current.completed else { return }
        state = .running(progress)
        if let run = progress.lastRun, !completedRuns.contains(where: { $0.id == run.id }) {
            completedRuns.append(run)
        }
        activity?.benchmark(completed: progress.completed, total: progress.total, lastRun: progress.lastRun)
    }

    private func finish(_ final: State) {
        state = final
        switch final {
        case .finished(let result):
            activity?.finish(
                detail: "\(result.runs.count) runs",
                tokensPerSecond: result.meanDecodeTokensPerSecond,
                timeToFirstTokenMs: Int(result.meanTtftMs)
            )
        case .failed(let message):
            activity?.fail(message)
        case .idle, .running:
            break
        }
        activity = nil
        if case .finished = final { onFinish(true) } else { onFinish(false) }
    }
}
