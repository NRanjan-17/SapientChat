/// What the chat is doing right now.
nonisolated enum ChatStatus: Equatable, Sendable {
    case idle
    /// First send downloads + loads the model, which can take a while.
    case loading(model: String)
    case generating
    case failed(String)
}
