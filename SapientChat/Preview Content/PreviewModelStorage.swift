// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

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
