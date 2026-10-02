import Foundation
import Testing
@testable import SapientChat

/// A `BenchmarkService` the test drives: it reports progress for each run
/// the test releases, and records whether it saw cancellation.
actor ControlledBenchmarkService: BenchmarkService {
    private(set) var started = false
    private(set) var sawCancellation = false
    private var release: [CheckedContinuation<Void, Never>] = []

    func benchmark(
        model: String,
        settings: BenchmarkSettings,
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult {
        started = true
        var runs: [BenchmarkRunResult] = []
        for completed in 1...settings.totalRuns {
            await withCheckedContinuation { release.append($0) }
            let run = BenchmarkRunResult(
                index: completed, isWarmup: false, ttftMs: 100, elapsedMs: 1_000, tokens: 10,
                decodeTokensPerSecond: Double(completed * 10), prefillTokensPerSecond: 50,
                hitEndOfTurn: false, footprintBytes: nil
            )
            runs.append(run)
            onProgress(BenchmarkProgress(completed: completed, total: settings.totalRuns, lastRun: run))
            if Task.isCancelled {
                sawCancellation = true
                break
            }
        }
        return BenchmarkResult(
            model: model, backend: "test", isMemoryMapped: true, contextLength: 3072, loadTimeMs: 1,
            promptTokens: 5, maxTokens: settings.maxTokens, warmupRuns: [], runs: runs, meanTtftMs: 100,
            meanDecodeTokensPerSecond: 15, minDecodeTokensPerSecond: 10, maxDecodeTokensPerSecond: 20,
            meanPrefillTokensPerSecond: 50, peakFootprintBytes: 1, thermalStart: "nominal",
            thermalEnd: "nominal", cancelled: sawCancellation, engineVersion: "test", method: "test",
            isSimulator: true
        )
    }

    var waitingRuns: Int { release.count }

    func releaseNextRun() {
        guard !release.isEmpty else { return }
        release.removeFirst().resume()
    }
}

@MainActor
struct BenchmarkViewModelTests {
    let service = ControlledBenchmarkService()

    private func makeViewModel(onFinish: @escaping (Bool) -> Void = { _ in }) -> BenchmarkViewModel {
        let viewModel = BenchmarkViewModel(model: "smollm2-1.7b", service: service, onFinish: onFinish)
        viewModel.settings.runs = 2
        viewModel.settings.warmup = 0
        return viewModel
    }

    @Test func reportsProgressThenTheResult() async {
        var finished: Bool?
        let viewModel = makeViewModel { finished = $0 }
        viewModel.run()
        #expect(viewModel.isRunning)

        #expect(await eventually { await service.waitingRuns == 1 })
        await service.releaseNextRun()
        #expect(await eventually { viewModel.progressForTest?.completed == 1 })
        #expect(viewModel.progressForTest?.total == 2)
        #expect(viewModel.progressForTest?.lastRun?.decodeTokensPerSecond == 10)

        #expect(await eventually { await service.waitingRuns == 1 })
        await service.releaseNextRun()
        #expect(await eventually { viewModel.result != nil })
        #expect(viewModel.result?.runs.count == 2)
        #expect(viewModel.result?.cancelled == false)
        #expect(finished == true, "the chat learns the model is loaded")
        #expect(!viewModel.isRunning)
    }

    @Test func cancelStopsAfterTheCurrentRun() async {
        let viewModel = makeViewModel()
        viewModel.run()
        #expect(await eventually { await service.waitingRuns == 1 })

        viewModel.cancel()
        await service.releaseNextRun()

        #expect(await eventually { viewModel.result != nil })
        #expect(await service.sawCancellation)
        #expect(viewModel.result?.cancelled == true)
        #expect(viewModel.result?.runs.count == 1)
    }

    @Test func refusesToRunWithoutAPrompt() async {
        let viewModel = makeViewModel()
        viewModel.settings.prompt = "  "
        #expect(!viewModel.canRun)
        viewModel.run()
        #expect(viewModel.state == .idle)
        #expect(await service.started == false)
    }

    @Test func resultExportsAsJSON() throws {
        let json = BenchmarkResult.sample.jsonText()
        let decoded = try JSONDecoder().decode(BenchmarkResult.self, from: Data(json.utf8))
        #expect(decoded == BenchmarkResult.sample)
    }
}

private extension BenchmarkViewModel {
    var progressForTest: BenchmarkProgress? {
        if case .running(let progress) = state { progress } else { nil }
    }
}
