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
    /// The backend each loaded model was loaded on.
    private var backends: [String: String] = [:]
    /// For each model's format: Automatic picks CPU + GPU only for memory-mapped ones.
    private let catalog: any ModelCatalogService

    init(
        cacheDirectory: URL = .cachesDirectory.appending(path: "sapient"),
        contextWindows: ContextWindowStore = .standard,
        catalog: any ModelCatalogService = SapientModelCatalog()
    ) {
        self.contextWindows = contextWindows
        self.catalog = catalog
        // Keep model downloads inside the app sandbox so the OS can reclaim
        // them and uninstalling the app removes them.
        setCacheDir(path: cacheDirectory.path(percentEncoded: false))
    }

    func load(model: String) async throws -> String {
        try await load(model: model, compute: nil)
    }

    /// Loads `model` on the Compute setting's backend, or on `compute` (a
    /// benchmark's pick), reloading it if it's in memory on another one. A
    /// model already loaded stays as it is for normal use, even if Automatic
    /// would now choose differently (e.g. the phone warmed up).
    func load(model: String, compute: ComputePreference?) async throws -> String {
        let backend = EngineBackendPreference.backend(
            for: catalog.chatModels().first { $0.alias == model }, override: compute
        )
        if let session = slots.use(model) {
            if compute == nil || backends[model] == backend {
                return session.backendLabel()
            }
            await generation?.value
            slots.remove(model)
            backends[model] = nil
        }
        await generation?.value
        // Free a slot BEFORE loading, so the slots are never exceeded, even briefly.
        if slots.models.count >= slots.capacity, let leastRecent = slots.models.last {
            slots.remove(leastRecent)
            backends[leastRecent] = nil
        }
        // Greedy decoding (no sampling fields set): deterministic, the right
        // default for small models. The context window is the user's pick for
        // this model, else the engine's (3072 tokens for models above 1.5B on
        // a phone, 8192 otherwise).
        var options = GenerationOptions(maxTokens: 512)
        options.contextLength = contextWindows.tokens(for: model).map(UInt32.init)
        // Compute setting: CPU + GPU by default, the GPU alone when hot or in
        // Low Power Mode, the CPU while serving in the background.
        options.backend = backend
        let loaded = try await loadSession(model: model, options: options)
        for released in slots.insert(model, session: loaded) { backends[released] = nil }
        backends[model] = backend
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
        backends[model] = nil
    }

    func unloadAll() async {
        await generation?.value
        slots.removeAll()
        backends.removeAll()
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
