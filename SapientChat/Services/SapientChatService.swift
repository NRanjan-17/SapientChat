import Foundation
import Sapient

/// `ChatService` and `BenchmarkService` backed by on-device SAPIENT
/// sessions. Holds up to four models (least recently used released first),
/// shared by chats, benchmarks and comparisons.
///
/// Uses SAPIENT's async exports, which run inference on the engine's own
/// thread pool, so no Swift thread is blocked while a model loads or decodes.
actor SapientChatService: ChatService {
    private var slots = LoadedSlots<LlmSession>()
    /// The engine call behind the latest reply or benchmark. It can outlive
    /// the Swift consumer by a token after a stop, so later work waits for it.
    private var generation: Task<Void, Never>?
    private let contextWindows: ContextWindowStore

    init(
        cacheDirectory: URL = .cachesDirectory.appending(path: "sapient"),
        contextWindows: ContextWindowStore = .standard
    ) {
        self.contextWindows = contextWindows
        // Keep model downloads inside the app sandbox so the OS can reclaim
        // them and uninstalling the app removes them.
        setCacheDir(path: cacheDirectory.path(percentEncoded: false))
    }

    func load(model: String) async throws -> String {
        if let session = slots.use(model) {
            return session.backendLabel()
        }
        await generation?.value
        // Free a slot BEFORE loading, so the slots are never exceeded, even briefly.
        if slots.models.count >= slots.capacity, let leastRecent = slots.models.last {
            slots.remove(leastRecent)
        }
        // Greedy decoding (no sampling fields set): deterministic, the right
        // default for small models. The context window is the user's pick for
        // this model, else the engine's (3072 tokens for models above 1.5B on
        // a phone, 8192 otherwise).
        var options = GenerationOptions(maxTokens: 512)
        options.contextLength = contextWindows.tokens(for: model).map(UInt32.init)
        // While the server runs in the background, models load on the CPU:
        // iOS doesn't allow GPU work from a background app.
        if EngineBackendPreference.cpuOnly() { options.backend = "cpu" }
        let loaded = try await loadSession(model: model, options: options)
        slots.insert(model, session: loaded)
        return loaded.backendLabel()
    }

    func details(model: String) -> LoadedModelDetails? {
        guard let session = slots.peek(model) else { return nil }
        return LoadedModelDetails(
            backend: session.backendLabel(),
            contextLength: Int(session.contextLength()),
            loadTimeMs: session.loadTimeMs()
        )
    }

    func loadedModels() -> [String] {
        slots.models
    }

    func unload(model: String) async {
        await generation?.value
        slots.remove(model)
    }

    func unloadAll() async {
        await generation?.value
        slots.removeAll()
    }

    /// The session for `model`, if loaded (marks it most recently used).
    func session(for model: String) -> LlmSession? {
        slots.use(model)
    }

    func reply(to history: [ChatMessage], model: String) throws -> AsyncThrowingStream<String, any Error> {
        guard let session = slots.use(model) else { throw ChatServiceError.noModelLoaded }
        let messages = history.map { Message(role: $0.role.rawValue, content: $0.text) }
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let listener = StreamListener(continuation: continuation)
        enqueueGeneration {
            do {
                _ = try await session.chatMessagesStream(messages: messages, listener: listener)
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    /// Runs `work` after the previous engine call, so replies and benchmarks
    /// never overlap (they would share the GPU and skew each other).
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
