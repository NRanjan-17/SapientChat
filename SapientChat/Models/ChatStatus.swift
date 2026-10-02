/// What the chat is doing right now.
nonisolated enum ChatStatus: Equatable, Sendable {
    case idle
    /// Fetching the model's files (first use only).
    case downloading(model: String, progress: DownloadProgress)
    /// Loading the model into memory.
    case loading(model: String)
    case generating
    case failed(String)
}
