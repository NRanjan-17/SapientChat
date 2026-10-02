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
    /// The chat's selected model; the benchmark runs on the same engine.
    let model: String
    var settings = BenchmarkSettings()
    private(set) var state: State = .idle

    @ObservationIgnored private let service: any BenchmarkService
    /// Told whether the benchmark finished (true) or failed (false).
    @ObservationIgnored private let onFinish: (Bool) -> Void
    @ObservationIgnored private var task: Task<Void, Never>?

    init(
        model: String,
        service: any BenchmarkService,
        state: State = .idle,
        onFinish: @escaping (Bool) -> Void = { _ in }
    ) {
        self.model = model
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
    }

    private func finish(_ final: State) {
        state = final
        if case .finished = final { onFinish(true) } else { onFinish(false) }
    }
}
