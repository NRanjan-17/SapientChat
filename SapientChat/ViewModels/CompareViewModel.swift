// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// Runs one prompt and one benchmark on two models, ONE AFTER THE OTHER:
/// model A is loaded, answers, is benchmarked, then loading model B
/// releases A. Only one model is in memory at a time (so a 1.7B model can
/// take part), and each gets the whole GPU/CPU, so the numbers are fair.
@Observable
final class CompareViewModel: Identifiable {
    let id = UUID()
    enum Phase: Equatable {
        case idle
        case running(String)
        case finished
        case failed(String)
    }

    let models: [PhoneModel]
    var modelA: String
    var modelB: String
    var prompt = "Explain in three sentences why the sky is blue."
    var settings = BenchmarkSettings(maxTokens: 128, runs: 2, warmup: 1)
    private(set) var results: [ModelComparison] = []
    private(set) var phase: Phase = .idle

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let device: DeviceStatus
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let liveActivities: any LiveActivityService
    @ObservationIgnored private var activity: LiveActivityTracker?

    init(
        services: AppServices, device: DeviceStatus, initialModel: String,
        liveActivities: any LiveActivityService = NoLiveActivities()
    ) {
        self.services = services
        self.liveActivities = liveActivities
        self.device = device
        models = services.catalog.chatModels()
        modelA = initialModel
        modelB = models.first { $0.alias != initialModel }?.alias ?? initialModel
    }

    var isRunning: Bool {
        if case .running = phase { true } else { false }
    }

    var canRun: Bool {
        !isRunning && modelA != modelB && settings.runs > 0
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// How much faster (positive) or slower model B decodes than model A, in percent.
    var decodeDifferencePercent: Double? {
        guard results.count == 2,
              let a = results[0].benchmark?.meanDecodeTokensPerSecond,
              let b = results[1].benchmark?.meanDecodeTokensPerSecond, a > 0
        else { return nil }
        return (b - a) / a * 100
    }

    /// Picks model A; picking B's model swaps the two, so they never match.
    func selectModelA(_ alias: String) {
        if alias == modelB { modelB = modelA }
        modelA = alias
    }

    /// Picks model B; picking A's model swaps the two.
    func selectModelB(_ alias: String) {
        if alias == modelA { modelA = modelB }
        modelB = alias
    }

    func displayName(of alias: String) -> String {
        models.first { $0.alias == alias }?.displayName ?? alias
    }

    func run() {
        guard canRun else { return }
        let lineup = [modelA, modelB]
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let settings = settings
        results = lineup.map { ModelComparison(model: $0, answer: "", benchmark: nil) }
        phase = .running("Starting…")
        task = Task { [weak self] in
            guard let self else { return }
            do {
                for (index, alias) in lineup.enumerated() {
                    try await compare(alias, at: index, prompt: prompt, settings: settings)
                }
                phase = .finished
            } catch is CancellationError {
                activity?.finish(detail: "Stopped")
                phase = .idle
            } catch ChatViewModelError.wontFit(let message) {
                activity?.fail(message)
                phase = .failed(message)
            } catch {
                activity?.fail(String(describing: error))
                phase = .failed(String(describing: error))
            }
            activity = nil
            device.refreshMemory()
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func compare(_ alias: String, at index: Int, prompt: String, settings: BenchmarkSettings) async throws {
        let name = displayName(of: alias)
        let activity = LiveActivityTracker(service: liveActivities, title: "Compare · model \(index + 1) of 2")
        activity.start(model: name)
        self.activity = activity
        _ = try await ModelPreparer(services: services, device: device).prepare(alias) { [self] step in
            activity.phase(step)
            phase = switch step {
            case .downloading(let progress): .running("Downloading \(name) · \(progress.text)")
            case .loading: .running("Loading \(name)…")
            }
        }
        try Task.checkCancellation()

        phase = .running("\(name) is answering…")
        activity.generating()
        for try await token in try await services.chat.reply(to: [ChatMessage(role: .user, text: prompt)], model: alias) {
            results[index].answer += token
            activity.token()
        }
        try Task.checkCancellation()

        phase = .running("Benchmarking \(name)…")
        activity.benchmark(completed: 0, total: settings.totalRuns, lastRun: nil)
        let result = try await services.benchmark.benchmark(model: alias, settings: settings) { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, case .running = phase else { return }
                phase = .running("Benchmarking \(name): run \(progress.completed) of \(progress.total)")
                activity.benchmark(completed: progress.completed, total: progress.total, lastRun: progress.lastRun)
            }
        }
        results[index].benchmark = result
        activity.finish(
            detail: "\(result.runs.count) runs",
            tokensPerSecond: result.meanDecodeTokensPerSecond,
            timeToFirstTokenMs: Int(result.meanTtftMs)
        )
        try Task.checkCancellation()
    }
}
