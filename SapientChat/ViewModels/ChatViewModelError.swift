/// Failures `ChatViewModel` raises itself (engine errors pass through).
nonisolated enum ChatViewModelError: Error {
    /// The model is estimated not to fit in the memory iOS allows.
    case wontFit(String)
}
