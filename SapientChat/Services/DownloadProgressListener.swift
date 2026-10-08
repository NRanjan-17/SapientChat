// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Sapient
import Synchronization

/// Receives SAPIENT's download progress (on an engine thread) and tells the
/// engine to stop once `cancel()` is called.
nonisolated final class DownloadProgressListener: DownloadListener {
    private let cancelled = Atomic<Bool>(false)
    private let onProgress: @Sendable (DownloadProgress) -> Void

    init(onProgress: @escaping @Sendable (DownloadProgress) -> Void) {
        self.onProgress = onProgress
    }

    func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    func onProgress(downloadedBytes: UInt64, totalBytes: UInt64) -> Bool {
        onProgress(DownloadProgress(downloadedBytes: downloadedBytes, totalBytes: totalBytes))
        return !cancelled.load(ordering: .relaxed)
    }
}
