import Foundation

/// One download per model for the whole app. A chat, the Models tab and API
/// requests all download through here: asking for a model that's already
/// downloading joins that download instead of starting another, and a
/// caller that goes away (a chat you leave) only stops following it; the
/// download carries on. `cancel(_:)` stops it for everyone.
///
/// Downloads keep going after you leave the app (with the API server on or
/// off): each asks iOS for a continued processing task, whose progress iOS
/// shows. If iOS cuts one off anyway, it resumes from where it stopped,
/// for the same callers, as soon as the app runs again.
final class DownloadCoordinator {
    private final class Job {
        var progress = DownloadProgress.starting
        var meter = DownloadSpeedMeter()
        var task: Task<Void, Never>?
        var waiters: [UUID: Waiter] = [:]
        /// The Dynamic Island, once a caller that wants one has joined.
        var island: LiveActivityTracker?
        /// iOS's background time for it, with the system's own progress UI.
        var backgroundWork: (any BackgroundDownload)?
        /// A caller asked for the Dynamic Island; shown if iOS's own progress isn't.
        var wantsIsland = false
        /// The app left the foreground while it ran: a failure is then
        /// likely iOS cutting it off, so it's resumed instead of reported.
        var wasBackgrounded = false
    }

    private struct Waiter {
        let onProgress: (DownloadProgress) -> Void
        let continuation: CheckedContinuation<Void, any Error>
    }

    private let downloads: any ModelDownloadService
    private let catalog: any ModelCatalogService
    private var jobs: [String: Job] = [:]
    /// Cut off while the app was suspended; resumed when it's active again.
    private var interrupted: [String: Job] = [:]
    private var isInForeground = true
    var liveActivities: any LiveActivityService = NoLiveActivities()
    var background: any BackgroundDownloadScheduler = NoBackgroundDownloads()
    /// Told every progress step of every download, then nil when it ends
    /// (the Models tab shows them all on their rows).
    var onChange: ((String, DownloadProgress?) -> Void)?

    init(downloads: any ModelDownloadService, catalog: any ModelCatalogService) {
        self.downloads = downloads
        self.catalog = catalog
    }

    func isDownloading(_ alias: String) -> Bool {
        jobs[alias] != nil || interrupted[alias] != nil
    }

    /// The app moved to the background: downloads keep going on their
    /// continued processing tasks, plus iOS's usual extra time.
    func appMovedToBackground() {
        isInForeground = false
        for job in jobs.values { job.wasBackgrounded = true }
        background.holdBriefly(active: !jobs.isEmpty)
    }

    /// The app is active again: resume any download iOS cut off.
    func appBecameActive() {
        isInForeground = true
        background.holdBriefly(active: false)
        let cutOff = interrupted
        interrupted.removeAll()
        for (alias, job) in cutOff { resume(alias, from: job) }
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
        let job = jobs[alias] ?? interrupted[alias] ?? start(alias)
        if showsIsland { job.wantsIsland = true }
        // iOS shows a continued processing task's progress itself.
        if job.backgroundWork == nil { showIslandIfWanted(alias, job) }
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
        if let job = interrupted.removeValue(forKey: alias) {
            end(alias, job, with: .failure(CancellationError()))
            return
        }
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
        if isInForeground {
            let name = catalog.chatModels().first { $0.alias == alias }?.displayName ?? alias
            job.backgroundWork = background.begin(model: alias, title: "Downloading \(name)")
            job.backgroundWork?.onExpire = { [weak job] in job?.wasBackgrounded = true }
            job.backgroundWork?.onRefused = { [weak self, weak job] in
                guard let self, let job else { return }
                job.backgroundWork = nil
                showIslandIfWanted(alias, job)
            }
        }
        onChange?(alias, .starting)
        return job
    }

    private func showIslandIfWanted(_ alias: String, _ job: Job) {
        guard job.wantsIsland, job.island == nil else { return }
        let island = LiveActivityTracker(service: liveActivities, title: "Download")
        island.start(model: catalog.chatModels().first { $0.alias == alias }?.displayName ?? alias)
        island.phase(.downloading(job.progress))
        job.island = island
    }

    /// Starts `alias` again (partial files resume) for the old job's callers.
    private func resume(_ alias: String, from old: Job) {
        old.backgroundWork?.finish(success: false)
        let job = start(alias)
        job.waiters = old.waiters
        job.wantsIsland = old.wantsIsland
        if let island = old.island {
            job.island = island
        } else if job.backgroundWork == nil {
            showIslandIfWanted(alias, job)
        }
    }

    private func progressed(_ alias: String, _ update: DownloadProgress) {
        guard let job = jobs[alias] else { return }
        var progress = update
        progress.bytesPerSecond = job.meter.record(update.downloadedBytes)
        job.progress = progress
        for waiter in job.waiters.values { waiter.onProgress(progress) }
        job.island?.phase(.downloading(progress))
        job.backgroundWork?.update(downloaded: progress.downloadedBytes, total: progress.totalBytes)
        onChange?(alias, progress)
    }

    private func finished(_ alias: String, _ result: Result<Void, any Error>) {
        guard let job = jobs.removeValue(forKey: alias) else { return }
        if case .failure(let error) = result, !(error is CancellationError), job.wasBackgrounded {
            // Most likely iOS stopping it in the background: carry on.
            if isInForeground { resume(alias, from: job) } else { interrupted[alias] = job }
            return
        }
        end(alias, job, with: result)
    }

    private func end(_ alias: String, _ job: Job, with result: Result<Void, any Error>) {
        if case .success = result { job.backgroundWork?.finish(success: true) } else { job.backgroundWork?.finish(success: false) }
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
        guard let waiter = (jobs[alias] ?? interrupted[alias])?.waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CancellationError())
    }
}
