/// `ModelStorageService` for SwiftUI previews: the first sample model is downloaded.
nonisolated struct PreviewModelStorage: ModelStorageService {
    func download(forRepo repoId: String) -> ModelDownload {
        repoId == PhoneModel.samples.first?.repoId ? .downloaded(bytes: 105_000_000) : .notDownloaded
    }

    func deleteDownload(forRepo repoId: String) throws {}

    func deleteAllDownloads() throws {}

    func totalDownloadBytes() -> UInt64 {
        105_000_000
    }
}
