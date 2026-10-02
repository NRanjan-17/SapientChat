/// The downloaded model files on this device.
nonisolated protocol ModelStorageService: Sendable {
    func download(forRepo repoId: String) -> ModelDownload
    /// Deletes one model's files.
    func deleteDownload(forRepo repoId: String) throws
    /// Deletes every downloaded model, tokenizers included.
    func deleteAllDownloads() throws
    /// Bytes used by all downloads.
    func totalDownloadBytes() -> UInt64
}
