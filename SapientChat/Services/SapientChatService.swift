import Foundation
import Sapient

/// `ChatService` backed by an on-device SAPIENT session.
///
/// Uses SAPIENT's async exports, which run inference on the engine's own
/// thread pool, so no Swift thread is blocked while a model loads or decodes.
actor SapientChatService: ChatService {
    private var session: LlmSession?
    /// The engine call behind the latest reply. It can outlive the Swift
    /// consumer by a token after a stop, so later work waits for it.
    private var generation: Task<Void, Never>?

    init(cacheDirectory: URL = .cachesDirectory.appending(path: "sapient")) {
        // Keep model downloads inside the app sandbox so the OS can reclaim
        // them and uninstalling the app removes them.
        setCacheDir(path: cacheDirectory.path(percentEncoded: false))
    }

    func load(model: String) async throws -> String {
        await generation?.value
        // Greedy decoding (no sampling fields set): deterministic, the right
        // default for small models.
        let loaded = try await loadSession(model: model, options: GenerationOptions(maxTokens: 512))
        session = loaded
        return loaded.backendLabel()
    }

    func reply(to prompt: String) throws -> AsyncThrowingStream<String, any Error> {
        guard let session else { throw ChatServiceError.noModelLoaded }
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let listener = StreamListener(continuation: continuation)
        let previous = generation
        generation = Task {
            // One turn at a time, so each turn commits to history in order.
            await previous?.value
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
}
