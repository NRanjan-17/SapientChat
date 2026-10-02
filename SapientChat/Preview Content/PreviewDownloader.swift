/// `ModelDownloadService` for SwiftUI previews: a fake 2-second download.
nonisolated struct PreviewDownloader: ModelDownloadService {
    func download(model: String, onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let total: UInt64 = 1_060_000_000
        for step in 1...8 {
            try await Task.sleep(for: .milliseconds(250))
            onProgress(DownloadProgress(downloadedBytes: total / 8 * UInt64(step), totalBytes: total))
        }
    }

    func downloadSize(model: String) async throws -> UInt64 {
        1_060_000_000
    }
}
