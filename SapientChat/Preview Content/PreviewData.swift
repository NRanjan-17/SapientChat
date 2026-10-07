import Foundation
import SwiftData

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
        PhoneModel(alias: "openhorizon/smollm2-135m-q4", repoId: "unsloth/SmolLM2-135M-Instruct-GGUF", params: "135M Q4_K_M", billions: 0.135),
        PhoneModel(alias: "openhorizon/qwen2.5-0.5b-q4", repoId: "Qwen/Qwen2.5-0.5B-Instruct-GGUF", params: "0.5B Q4_K_M", billions: 0.5),
        PhoneModel(alias: "openhorizon/smollm2-1.7b", repoId: "HuggingFaceTB/SmolLM2-1.7B-Instruct", params: "1.7B", billions: 1.7),
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

extension AppServices {
    static var preview: AppServices {
        AppServices(
            chat: PreviewChatService(),
            benchmark: PreviewBenchmarkService(),
            catalog: PreviewModelCatalog(),
            thermal: PreviewThermalService(),
            memory: PreviewMemoryService(),
            storage: PreviewModelStorage(),
            downloads: PreviewDownloader()
        )
    }
}

/// An in-memory SwiftData store with two sample chats.
@MainActor
enum PreviewStore {
    static let container: ModelContainer = {
        do {
            return try ModelContainer(
                for: Conversation.self, StoredMessage.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        } catch {
            fatalError("Preview store: \(error)")
        }
    }()

    static let store: SwiftDataConversationStore = {
        let store = SwiftDataConversationStore(context: container.mainContext)
        let chat = store.createConversation(model: PhoneModel.samples[0].alias)
        chat.title = "Offline AI"
        for message in ChatMessage.samples {
            store.append(message.role, text: message.text, to: chat)
        }
        _ = store.createConversation(model: PhoneModel.samples[2].alias)
        return store
    }()
}

extension ChatListViewModel {
    static var preview: ChatListViewModel {
        ChatListViewModel(services: .preview, store: PreviewStore.store)
    }
}

extension ModelSelectorViewModel {
    static var preview: ModelSelectorViewModel {
        ModelSelectorViewModel(
            selected: PhoneModel.samples[0].alias,
            services: .preview,
            device: DeviceStatus(memoryService: PreviewMemoryService(), thermalService: PreviewThermalService()),
            onSelect: { _ in }
        )
    }
}

extension ModelManagerViewModel {
    static var preview: ModelManagerViewModel {
        ModelManagerViewModel(
            services: .preview,
            device: DeviceStatus(memoryService: PreviewMemoryService(), thermalService: PreviewThermalService()),
            onNewChat: { _ in }
        )
    }
}

extension CompareViewModel {
    static var preview: CompareViewModel {
        CompareViewModel(
            services: .preview,
            device: DeviceStatus(memoryService: PreviewMemoryService(), thermalService: PreviewThermalService()),
            initialModel: PhoneModel.samples[0].alias
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

nonisolated extension ReplyStats {
    static let sample = ReplyStats(
        firstTokenMs: 312, tokensPerSecond: 27.4, pieces: 128, durationMs: 4_800,
        loadMs: 1_840, model: "openhorizon/smollm2-1.7b-q4", backend: "wgpu (Apple GPU (Metal))"
    )
}
