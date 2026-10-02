import Foundation
import Sapient

extension SapientChatService: BenchmarkService {
    /// Runs on the same session as the chat (no second model in memory) and
    /// queues behind any reply in flight. Chat history is left untouched.
    func benchmark(
        model: String,
        settings: BenchmarkSettings,
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult {
        _ = try await load(model: model)
        guard let session = session(for: model) else { throw ChatServiceError.noModelLoaded }

        let listener = BenchmarkProgressListener(onProgress: onProgress)
        let options = BenchmarkOptions(
            prompt: settings.prompt,
            maxTokens: UInt32(settings.maxTokens),
            runs: UInt32(settings.runs),
            warmup: UInt32(settings.warmup)
        )
        let run = enqueueGeneration {
            try await session.benchmarkAsync(options: options, listener: listener)
        }
        let report = try await withTaskCancellationHandler {
            try await run.value
        } onCancel: {
            listener.cancel()
        }
        return BenchmarkResult(report)
    }
}

nonisolated private extension BenchmarkResult {
    init(_ report: BenchmarkReport) {
        #if targetEnvironment(simulator)
        let isSimulator = true
        #else
        let isSimulator = false
        #endif
        self.init(
            model: report.model,
            backend: report.backendLabel,
            isMemoryMapped: report.isMmap,
            contextLength: Int(report.contextLength),
            loadTimeMs: report.loadTimeMs,
            promptTokens: Int(report.promptTokens),
            maxTokens: Int(report.maxTokens),
            warmupRuns: report.warmupRuns.map(BenchmarkRunResult.init),
            runs: report.runs.map(BenchmarkRunResult.init),
            meanTtftMs: report.meanTtftMs,
            meanDecodeTokensPerSecond: report.meanDecodeTokensPerSec,
            minDecodeTokensPerSecond: report.minDecodeTokensPerSec,
            maxDecodeTokensPerSecond: report.maxDecodeTokensPerSec,
            meanPrefillTokensPerSecond: report.meanPrefillTokensPerSec,
            peakFootprintBytes: report.peakFootprintBytes,
            thermalStart: "\(report.thermalStart)",
            thermalEnd: "\(report.thermalEnd)",
            cancelled: report.cancelled,
            engineVersion: report.sapientVersion,
            method: report.method,
            isSimulator: isSimulator
        )
    }
}
