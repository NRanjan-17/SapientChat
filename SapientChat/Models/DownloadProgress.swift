/// Bytes received for a model download.
nonisolated struct DownloadProgress: Equatable, Sendable {
    let downloadedBytes: UInt64
    /// 0 when the Hub didn't report sizes.
    let totalBytes: UInt64

    static let starting = DownloadProgress(downloadedBytes: 0, totalBytes: 0)

    /// 0…1, or nil when the total is unknown.
    var fraction: Double? {
        totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : nil
    }

    /// "412 MB of 1.06 GB" (or "412 MB" when the total is unknown).
    var text: String {
        totalBytes > 0
            ? "\(Format.bytes(downloadedBytes)) of \(Format.bytes(totalBytes))"
            : Format.bytes(downloadedBytes)
    }
}
