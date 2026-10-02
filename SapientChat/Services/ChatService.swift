/// Runs a chat model. The only layer that talks to the inference engine.
nonisolated protocol ChatService: Sendable {
    /// Loads `model`, downloading it on first use, and makes it the active
    /// session. Returns a label for the hardware it runs on.
    func load(model: String) async throws -> String

    /// Streams the reply to `prompt` token by token, continuing the
    /// conversation. Cancelling the task that consumes the stream stops
    /// generation; the partial reply stays in the conversation history.
    func reply(to prompt: String) async throws -> AsyncThrowingStream<String, any Error>

    /// Forgets the conversation history, once any reply in flight has finished.
    func reset() async
}
