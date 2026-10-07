import Foundation

/// Bytes received for a model download.
nonisolated struct DownloadProgress: Equatable, Sendable {
    let downloadedBytes: UInt64
    /// 0 when the Hub didn't report sizes.
    let totalBytes: UInt64
    /// Recent speed; nil until measured.
    var bytesPerSecond: Double?

    static let starting = DownloadProgress(downloadedBytes: 0, totalBytes: 0)

    /// 0…1, or nil when the total is unknown.
    var fraction: Double? {
        totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : nil
    }

    /// Time left at the current speed; nil when speed or total is unknown.
    var secondsRemaining: Double? {
        guard let bytesPerSecond, bytesPerSecond > 0, totalBytes > downloadedBytes else { return nil }
        return Double(totalBytes - downloadedBytes) / bytesPerSecond
    }

    /// "8.2 MB/s", or nil until measured.
    var speedText: String? {
        bytesPerSecond.map { Format.bytes(UInt64(max(0, $0))) + "/s" }
    }

    /// "2 min left" / "40 sec left", or nil when unknown.
    var remainingText: String? {
        secondsRemaining.map { seconds in
            Duration.seconds(max(1, seconds.rounded()))
                .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 1))
                + " left"
        }
    }

    /// "412 MB of 1.06 GB" (or "412 MB" when the total is unknown).
    var text: String {
        totalBytes > 0
            ? "\(Format.bytes(downloadedBytes)) of \(Format.bytes(totalBytes))"
            : Format.bytes(downloadedBytes)
    }
}
