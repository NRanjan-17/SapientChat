/// What the engine reports about a loaded model.
nonisolated struct LoadedModelDetails: Equatable, Sendable {
    let backend: String
    /// Conversation window allocated, in tokens.
    let contextLength: Int
    let loadTimeMs: UInt64
}
