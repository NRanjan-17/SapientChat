/// Runs chat models. The only layer that talks to the inference engine.
/// Keeps up to `LoadedSlots.defaultCapacity` (4) models in memory.
nonisolated protocol ChatService: Sendable {
    /// Loads `model` (downloading on first use) and marks it most recently
    /// used. Already loaded: just marks it. With both slots full, the least
    /// recently used model is released first. Returns a hardware label.
    func load(model: String) async throws -> String

    /// Models in memory, most recently used first.
    func loadedModels() async -> [String]

    /// What the engine reports about a loaded `model` (nil if not loaded).
    /// Doesn't count as using it.
    func details(model: String) async -> LoadedModelDetails?

    /// Releases one model's memory.
    func unload(model: String) async

    /// Releases every model.
    func unloadAll() async

    /// Streams `model`'s reply to `history` (oldest first, ending with the
    /// user's new message). Stateless: each chat sends its own history, and
    /// the engine's prefix cache keeps re-sent history cheap. Cancelling the
    /// consuming task stops generation.
    func reply(to history: [ChatMessage], model: String) async throws -> AsyncThrowingStream<String, any Error>
}
