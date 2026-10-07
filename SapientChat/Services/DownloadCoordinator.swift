import Foundation

/// One download per model for the whole app. A chat, the Models tab and API
/// requests all download through here: asking for a model that's already
/// downloading joins that download instead of starting another, and a
/// caller that goes away (a chat you leave) only stops following it; the
/// download carries on. `cancel(_:)` stops it for everyone.
final class DownloadCoordinator {
    private final class Job {
        var progress = DownloadProgress.starting
        var meter = DownloadSpeedMeter()
        var task: Task<Void, Never>?
        var waiters: [UUID: Waiter] = [:]
        /// The Dynamic Island, once a caller that wants one has joined.
        var island: LiveActivityTracker?
    }

    private struct Waiter {
        let onProgress: (DownloadProgress) -> Void
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let downloads: any ModelDownloadService
    private let catalog: any ModelCatalogService
    private var jobs: [String: Job] = [:]
    var liveActivities: any LiveActivityService = NoLiveActivities()
    /// Told every progress step of every download, then nil when it ends
    /// (the Models tab shows them all on their rows).
    var onChange: ((String, DownloadProgress?) -> Void)?

    init(downloads: any ModelDownloadService, catalog: any ModelCatalogService) {
        self.downloads = downloads
        self.catalog = catalog
    }

    func isDownloading(_ alias: String) -> Bool {
        jobs[alias] != nil
    }

    /// Downloads `alias`, or joins its download if one is running, and
    /// returns when it's done. Cancelling the caller stops only the caller.
    /// - Parameter showsIsland: show the download in the Dynamic Island
    ///   (API requests show their own activity instead).
    func download(
        _ alias: String,
        showsIsland: Bool = true,
        onProgress: @escaping (DownloadProgress) -> Void
    ) async throws {
        try Task.checkCancellation()
        let job = jobs[alias] ?? start(alias)
        if showsIsland && job.island == nil {
            let island = LiveActivityTracker(service: liveActivities, title: "Download")
            island.start(model: catalog.chatModels().first { $0.alias == alias }?.displayName ?? alias)
            island.phase(.downloading(job.progress))
            job.island = island
        }
        // Joining a download that's under way: show where it is now.
        if job.progress != .starting { onProgress(job.progress) }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                job.waiters[id] = Waiter(onProgress: onProgress, continuation: continuation)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.leave(alias, id: id) }
        }
    }

    /// Stops `alias`'s download for everyone waiting on it.
    func cancel(_ alias: String) {
        jobs[alias]?.task?.cancel()
    }

    // MARK: Private

    private func start(_ alias: String) -> Job {
        let job = Job()
        jobs[alias] = job
        let downloads = downloads
        job.task = Task { [weak self] in
            let (updates, sink) = AsyncStream<DownloadProgress>.makeStream()
            let work = Task {
                defer { sink.finish() }
                try await downloads.download(model: alias) { sink.yield($0) }
            }
            await withTaskCancellationHandler {
                for await progress in updates { self?.progressed(alias, progress) }
            } onCancel: {
                work.cancel()
            }
            self?.finished(alias, await work.result)
        }
        onChange?(alias, .starting)
        return job
    }

    private func progressed(_ alias: String, _ update: DownloadProgress) {
        guard let job = jobs[alias] else { return }
        var progress = update
        progress.bytesPerSecond = job.meter.record(update.downloadedBytes)
        job.progress = progress
        for waiter in job.waiters.values { waiter.onProgress(progress) }
        job.island?.phase(.downloading(progress))
        onChange?(alias, progress)
    }

    private func finished(_ alias: String, _ result: Result<Void, any Error>) {
        guard let job = jobs.removeValue(forKey: alias) else { return }
        for waiter in job.waiters.values {
            waiter.continuation.resume(with: result)
        }
        switch result {
        case .success: job.island?.finish(detail: "Downloaded")
        case .failure(let error) where error is CancellationError: job.island?.finish(detail: "Cancelled")
        case .failure(let error): job.island?.fail(String(describing: error))
        }
        onChange?(alias, nil)
    }

    /// A caller went away: it stops waiting; the download goes on.
    private func leave(_ alias: String, id: UUID) {
        guard let waiter = jobs[alias]?.waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CancellationError())
    }
}
