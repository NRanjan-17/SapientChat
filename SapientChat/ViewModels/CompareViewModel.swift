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

    init(services: AppServices, device: DeviceStatus, initialModel: String) {
        self.services = services
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
                phase = .idle
            } catch ChatViewModelError.wontFit(let message) {
                phase = .failed(message)
            } catch {
                phase = .failed(String(describing: error))
            }
            device.refreshMemory()
        }
    }

    func cancel() {
        task?.cancel()
    }

    private func compare(_ alias: String, at index: Int, prompt: String, settings: BenchmarkSettings) async throws {
        let name = displayName(of: alias)
        _ = try await ModelPreparer(services: services, device: device).prepare(alias) { step in
            phase = switch step {
            case .downloading(let progress): .running("Downloading \(name) · \(progress.text)")
            case .loading: .running("Loading \(name)…")
            }
        }
        try Task.checkCancellation()

        phase = .running("\(name) is answering…")
        for try await token in try await services.chat.reply(to: [ChatMessage(role: .user, text: prompt)], model: alias) {
            results[index].answer += token
        }
        try Task.checkCancellation()

        phase = .running("Benchmarking \(name)…")
        let result = try await services.benchmark.benchmark(model: alias, settings: settings) { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, case .running = phase else { return }
                phase = .running("Benchmarking \(name): run \(progress.completed) of \(progress.total)")
            }
        }
        results[index].benchmark = result
        try Task.checkCancellation()
    }
}
