/// Runs a chat model. The only layer that talks to the inference engine.
nonisolated protocol ChatService: Sendable {
    /// Loads `model`, downloading it on first use, and makes it the active
    /// model (releasing the previous one first). Loading the model that is
    /// already active does nothing. Returns a label for the hardware.
    func load(model: String) async throws -> String

    /// The alias of the active model, if one is loaded.
    func loadedModel() async -> String?

    /// Releases the active model's memory.
    func unload() async

    /// Streams the reply that follows `history` (oldest first, ending with
    /// the user's new message). Stateless: every chat sends its own history,
    /// and the engine's prefix cache keeps re-sent history cheap. Cancelling
    /// the consuming task stops generation.
    func reply(to history: [ChatMessage]) async throws -> AsyncThrowingStream<String, any Error>
}
