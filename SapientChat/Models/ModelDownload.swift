/// Whether a model's files are on this device.
nonisolated enum ModelDownload: Equatable, Sendable {
    case notDownloaded
    /// An earlier download stopped part-way; the next one resumes it.
    case partial(bytes: UInt64)
    case downloaded(bytes: UInt64)

    var isDownloaded: Bool {
        if case .downloaded = self { true } else { false }
    }

    /// Bytes on disk, complete or not.
    var bytes: UInt64 {
        switch self {
        case .notDownloaded: 0
        case .partial(let bytes), .downloaded(let bytes): bytes
        }
    }
}
