/// Downloads models without loading them.
nonisolated protocol ModelDownloadService: Sendable {
    /// Fetches everything `model` needs to load later, offline. Reports
    /// progress about four times a second. Cancelling the calling task
    /// stops it (throws `CancellationError`); partial files resume next time.
    func download(model: String, onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws

    /// Bytes a download will fetch (0 if unknown).
    func downloadSize(model: String) async throws -> UInt64
}
