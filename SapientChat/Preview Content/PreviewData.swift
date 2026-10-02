import Foundation

// Self-contained sample data for SwiftUI previews.

nonisolated extension ChatMessage {
    static let samples: [ChatMessage] = [
        ChatMessage(role: .user, text: "What can you do offline?"),
        ChatMessage(role: .assistant, text: "Everything in this chat runs on your device, so I work without a network connection once the model is downloaded."),
        ChatMessage(role: .user, text: "Nice. Keep answers short."),
    ]
}

nonisolated extension PhoneModel {
    static let samples: [PhoneModel] = [
        PhoneModel(alias: "smollm2-135m-q4", params: "135M Q4_K_M", billions: 0.135),
        PhoneModel(alias: "qwen2.5-0.5b-q4", params: "0.5B Q4_K_M", billions: 0.5),
        PhoneModel(alias: "llama3.2-1b-q4", params: "1B Q4_K_M", billions: 1),
    ]
}

nonisolated extension BenchmarkRunResult {
    static let samples: [BenchmarkRunResult] = [
        BenchmarkRunResult(index: 1, isWarmup: true, ttftMs: 410, elapsedMs: 5_200, tokens: 128,
                           decodeTokensPerSecond: 24.6, prefillTokensPerSecond: 95, hitEndOfTurn: false,
                           footprintBytes: 1_850_000_000),
        BenchmarkRunResult(index: 1, isWarmup: false, ttftMs: 300, elapsedMs: 4_900, tokens: 128,
                           decodeTokensPerSecond: 27.7, prefillTokensPerSecond: 130, hitEndOfTurn: false,
                           footprintBytes: 1_860_000_000),
        BenchmarkRunResult(index: 2, isWarmup: false, ttftMs: 290, elapsedMs: 4_800, tokens: 128,
                           decodeTokensPerSecond: 28.4, prefillTokensPerSecond: 134, hitEndOfTurn: false,
                           footprintBytes: 1_860_000_000),
    ]
}

nonisolated extension BenchmarkResult {
    static let sample = BenchmarkResult(
        model: "smollm2-1.7b-q4", backend: "wgpu (Apple GPU (Metal))", isMemoryMapped: true,
        contextLength: 3072, loadTimeMs: 2_300, promptTokens: 38, maxTokens: 128,
        warmupRuns: [BenchmarkRunResult.samples[0]], runs: Array(BenchmarkRunResult.samples.dropFirst()),
        meanTtftMs: 295, meanDecodeTokensPerSecond: 28.05, minDecodeTokensPerSecond: 27.7,
        maxDecodeTokensPerSecond: 28.4, meanPrefillTokensPerSecond: 132, peakFootprintBytes: 1_900_000_000,
        thermalStart: "nominal", thermalEnd: "fair", cancelled: false, engineVersion: "preview",
        method: "preview data", isSimulator: true
    )
}

extension ChatViewModel {
    static var preview: ChatViewModel {
        ChatViewModel(
            chatService: PreviewChatService(),
            benchmarkService: PreviewBenchmarkService(),
            catalog: PreviewModelCatalog(),
            thermalService: PreviewThermalService(),
            memoryService: PreviewMemoryService(),
            messages: ChatMessage.samples
        )
    }

    static var emptyPreview: ChatViewModel {
        ChatViewModel(
            chatService: PreviewChatService(),
            benchmarkService: PreviewBenchmarkService(),
            catalog: PreviewModelCatalog(),
            thermalService: PreviewThermalService(),
            memoryService: PreviewMemoryService()
        )
    }
}

extension BenchmarkViewModel {
    static var preview: BenchmarkViewModel {
        BenchmarkViewModel(model: "smollm2-1.7b-q4", service: PreviewBenchmarkService())
    }

    static var finishedPreview: BenchmarkViewModel {
        BenchmarkViewModel(model: "smollm2-1.7b-q4", service: PreviewBenchmarkService(), state: .finished(.sample))
    }
}
