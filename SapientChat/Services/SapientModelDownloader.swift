import Sapient

/// `ModelDownloadService` over SAPIENT's `downloadModel`.
nonisolated struct SapientModelDownloader: ModelDownloadService {
    func download(model: String, onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let listener = DownloadProgressListener(onProgress: onProgress)
        do {
            try await withTaskCancellationHandler {
                try await downloadModel(model: model, listener: listener)
            } onCancel: {
                listener.cancel()
            }
        } catch SapientError.Cancelled {
            throw CancellationError()
        }
    }

    func downloadSize(model: String) async throws -> UInt64 {
        try await modelDownloadSize(model: model)
    }
}
