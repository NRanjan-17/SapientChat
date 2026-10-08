// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// One download per model for the whole app. A chat, the Models tab and API
/// requests all download through here: asking for a model that's already
/// downloading joins that download instead of starting another, and a
/// caller that goes away (a chat you leave) only stops following it; the
/// download carries on. `cancel(_:)` stops it for everyone.
///
/// Downloads keep going after you leave the app (with the API server on or
/// off): ONE continued processing task covers all of them, and iOS shows
/// their combined progress. When iOS isn't showing it, one Live Activity
/// lists every model downloading (the Dynamic Island shows a single
/// activity, so one per download hid the rest). If iOS cuts a download off
/// anyway, it resumes from where it stopped, for the same callers, as soon
/// as the app runs again.
final class DownloadCoordinator {
    private final class Job {
        var progress = DownloadProgress.starting
        var meter = DownloadSpeedMeter()
        var task: Task<Void, Never>?
        var waiters: [UUID: Waiter] = [:]
        /// A caller asked for the Dynamic Island (API requests show their own).
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
    /// iOS's background time for every download running now.
    private var sharedWork: (any BackgroundDownload)?
    /// The app's own activity, when iOS isn't showing the downloads.
    private var island: DownloadsLiveActivity?
    /// Bytes of downloads that finished while others still run, so the
    /// combined progress doesn't jump back when one completes.
    private var finishedBytes: UInt64 = 0
    private var failures: [String] = []

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

    /// The app moved to the background: downloads keep going on the
    /// continued processing task, plus iOS's usual extra time.
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
        if showsIsland, !job.wantsIsland {
            job.wantsIsland = true
            refresh()
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
        // One background task covers every download; later ones join it.
        if sharedWork == nil, isInForeground {
            let work = background.begin(model: alias, title: "Downloading \(name(of: alias))")
            work?.onExpire = { [weak self] in
                guard let self else { return }
                for job in jobs.values { job.wasBackgrounded = true }
            }
            work?.onRefused = { [weak self] in
                self?.sharedWork = nil
                self?.refresh()
            }
            sharedWork = work
        }
        onChange?(alias, .starting)
        refresh()
        return job
    }

    /// Starts `alias` again (partial files resume) for the old job's callers.
    private func resume(_ alias: String, from old: Job) {
        let job = start(alias)
        job.waiters = old.waiters
        job.wantsIsland = old.wantsIsland
        refresh()
    }

    private func progressed(_ alias: String, _ update: DownloadProgress) {
        guard let job = jobs[alias] else { return }
        var progress = update
        progress.bytesPerSecond = job.meter.record(update.downloadedBytes)
        job.progress = progress
        for waiter in job.waiters.values { waiter.onProgress(progress) }
        onChange?(alias, progress)
        refresh()
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
        for waiter in job.waiters.values {
            waiter.continuation.resume(with: result)
        }
        switch result {
        case .success:
            finishedBytes += max(job.progress.downloadedBytes, job.progress.totalBytes)
        case .failure(let error) where error is CancellationError:
            break
        case .failure:
            failures.append(name(of: alias))
        }
        onChange?(alias, nil)
        refresh()
    }

    /// Brings the shared background task and the downloads activity up to
    /// date, and ends both once nothing is downloading.
    private func refresh() {
        let active = jobs.merging(interrupted) { current, _ in current }
            .sorted { $0.key < $1.key }
        guard !active.isEmpty else {
            let succeeded = failures.isEmpty
            sharedWork?.finish(success: succeeded)
            sharedWork = nil
            island?.finish(failures: failures)
            island = nil
            finishedBytes = 0
            failures = []
            return
        }
        let downloaded = finishedBytes + active.reduce(0) { $0 + $1.value.progress.downloadedBytes }
        let total = finishedBytes + active.reduce(0) { $0 + $1.value.progress.totalBytes }
        let items = active.map { alias, job in
            SapientActivityAttributes.DownloadItem(name: name(of: alias), progress: job.progress.fraction)
        }
        let title = items.count == 1 ? "Downloading \(items[0].name)" : "Downloading \(items.count) models"
        let subtitle = items.map { item in
            item.progress.map { "\(item.name) \(Int(($0 * 100).rounded()))%" } ?? item.name
        }.joined(separator: " · ")
        sharedWork?.update(downloaded: downloaded, total: total, title: title, subtitle: subtitle)

        // iOS shows a continued processing task's progress itself.
        let wantsIsland = active.contains { $0.value.wantsIsland }
        if sharedWork == nil, wantsIsland {
            if island == nil { island = DownloadsLiveActivity(service: liveActivities) }
            island?.show(items, progress: total > 0 ? Double(downloaded) / Double(total) : nil)
        }
    }

    private func name(of alias: String) -> String {
        catalog.chatModels().first { $0.alias == alias }?.displayName ?? alias
    }

    /// A caller went away: it stops waiting; the download goes on.
    private func leave(_ alias: String, id: UUID) {
        guard let waiter = (jobs[alias] ?? interrupted[alias])?.waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: CancellationError())
    }
}
