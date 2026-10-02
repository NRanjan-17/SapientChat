import Foundation
import Sapient

/// `ChatService` and `BenchmarkService` backed by one on-device SAPIENT
/// session, so chatting and benchmarking share a single loaded model.
///
/// Uses SAPIENT's async exports, which run inference on the engine's own
/// thread pool, so no Swift thread is blocked while a model loads or decodes.
actor SapientChatService: ChatService {
    private(set) var session: LlmSession?
    private var loadedModel: String?
    /// The engine call behind the latest reply or benchmark. It can outlive
    /// the Swift consumer by a token after a stop, so later work waits for it.
    private var generation: Task<Void, Never>?

    init(cacheDirectory: URL = .cachesDirectory.appending(path: "sapient")) {
        // Keep model downloads inside the app sandbox so the OS can reclaim
        // them and uninstalling the app removes them.
        setCacheDir(path: cacheDirectory.path(percentEncoded: false))
    }

    func load(model: String) async throws -> String {
        await generation?.value
        if let session, loadedModel == model {
            return session.backendLabel()
        }
        // Release the current model BEFORE loading the next one: two models
        // in memory at once is the fastest way past a phone's memory limit.
        session = nil
        loadedModel = nil
        // Greedy decoding (no sampling fields set): deterministic, the right
        // default for small models. The context window is left to the engine
        // (3072 tokens for models above 1.5B on a phone, 8192 otherwise).
        let loaded = try await loadSession(model: model, options: GenerationOptions(maxTokens: 512))
        session = loaded
        loadedModel = model
        return loaded.backendLabel()
    }

    func reply(to prompt: String) throws -> AsyncThrowingStream<String, any Error> {
        guard let session else { throw ChatServiceError.noModelLoaded }
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let listener = StreamListener(continuation: continuation)
        enqueueGeneration {
            do {
                _ = try await session.chatStreamAsync(userMessage: prompt, listener: listener)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    func reset() async {
        await generation?.value
        session?.reset()
    }

    /// Runs `work` after the previous engine call, so turns and benchmarks
    /// never overlap and each turn commits to history in order.
    @discardableResult
    func enqueueGeneration<T: Sendable>(
        _ work: @escaping @Sendable () async throws -> T
    ) -> Task<T, any Error> {
        let previous = generation
        let task = Task {
            await previous?.value
            return try await work()
        }
        generation = Task { _ = try? await task.value }
        return task
    }
}
