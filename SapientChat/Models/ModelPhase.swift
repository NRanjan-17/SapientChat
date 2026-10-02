/// A step in getting a model ready to use.
nonisolated enum ModelPhase: Equatable, Sendable {
    case downloading(DownloadProgress)
    case loading
}
