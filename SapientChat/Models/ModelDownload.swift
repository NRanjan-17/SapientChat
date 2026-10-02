/// Whether a model's files are on this device.
nonisolated enum ModelDownload: Equatable, Sendable {
    case notDownloaded
    case downloaded(bytes: UInt64)

    var isDownloaded: Bool {
        if case .downloaded = self { true } else { false }
    }
}
