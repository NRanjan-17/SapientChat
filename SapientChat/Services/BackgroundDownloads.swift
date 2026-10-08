// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import BackgroundTasks
import Foundation
import OSLog
import UIKit

/// Keeps the app running while a model downloads after you leave it, so a
/// download finishes whether or not the API server's background mode is on.
/// Behind a protocol so tests can stand in for iOS.
protocol BackgroundDownloadScheduler: AnyObject {
    /// Asks iOS to keep downloading `model` in the background; nil when it
    /// can't be asked. iOS answers later: a refusal calls `onRefused`.
    /// Only works while the app is in the foreground.
    func begin(model: String, title: String) -> (any BackgroundDownload)?
    /// The app is leaving: ask for iOS's usual extra time while `active`.
    func holdBriefly(active: Bool)
}

/// One download iOS lets run in the background, with its progress shown by
/// the system (Dynamic Island, Lock Screen).
protocol BackgroundDownload: AnyObject {
    func update(downloaded: UInt64, total: UInt64)
    func finish(success: Bool)
    /// Called if iOS stops the background time before the download ends.
    var onExpire: (() -> Void)? { get set }
    /// Called if iOS declines the request (no system progress UI then).
    var onRefused: (() -> Void)? { get set }
}

/// The real one: iOS 26's continued processing tasks (`BGContinuedProcessingTask`),
/// plus `beginBackgroundTask` as the short fallback.
final class ContinuedProcessingDownloads: BackgroundDownloadScheduler {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in the Info.plists.
    static var identifierPrefix: String {
        (Bundle.main.bundleIdentifier ?? "SapientChat") + ".download"
    }

    private var pending: [String: Work] = [:]
    private var briefHold: UIBackgroundTaskIdentifier = .invalid
    private let log = Logger(subsystem: "SapientChat", category: "BackgroundDownload")
    /// Whether iOS accepted the launch handler. Submitting without one
    /// isn't an error iOS returns: it aborts the app.
    private var isRegistered = false

    /// A new task identifier that iOS matches against `<prefix>.*`: the part
    /// after the prefix must be one segment, so a random ID of letters and
    /// digits, never anything from a model's name (a name like "qwen2.5-0.5b"
    /// has dots; an identifier built from it matched nothing and iOS ended
    /// the app). Works for any model, including ones added later.
    static func newIdentifier() -> String {
        identifierPrefix + "." + UUID().uuidString.filter { $0.isLetter || $0.isNumber }
    }

    /// Registers the launch handler. Call once, while the app launches.
    init() {
        isRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifierPrefix + ".*", using: .main) { [weak self] task in
            guard let task = task as? BGContinuedProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            MainActor.assumeIsolated { self?.started(task) }
        }
        if !isRegistered {
            log.error("Couldn't register \(Self.identifierPrefix, privacy: .public).*; downloads won't get background time")
        }
    }

    func begin(model: String, title: String) -> (any BackgroundDownload)? {
        guard isRegistered else { return nil }
        let identifier = Self.newIdentifier()
        let request = BGContinuedProcessingTaskRequest(identifier: identifier, title: title, subtitle: "Starting…")
        // Fail rather than queue: a queued request might start after the
        // download is done; the brief hold and resume-on-return cover it.
        request.strategy = .fail
        let work = Work(identifier: identifier)
        pending[identifier] = work
        let log = log
        Task { [weak self] in
            do {
                try await BGTaskScheduler.shared.submitTaskRequest(request)
                log.info("Continued processing accepted for \(model, privacy: .public)")
            } catch {
                log.info("Continued processing refused for \(model, privacy: .public): \(error.localizedDescription, privacy: .public)")
                self?.pending[identifier] = nil
                work.refused()
            }
        }
        return work
    }

    func holdBriefly(active: Bool) {
        if active, briefHold == .invalid {
            briefHold = UIApplication.shared.beginBackgroundTask(withName: "Finish model downloads") { [weak self] in
                self?.holdBriefly(active: false)
            }
        } else if !active, briefHold != .invalid {
            UIApplication.shared.endBackgroundTask(briefHold)
            briefHold = .invalid
        }
    }

    private func started(_ task: BGContinuedProcessingTask) {
        guard let work = pending.removeValue(forKey: task.identifier) else {
            // Its download already ended (or the app relaunched): nothing to keep alive.
            task.setTaskCompleted(success: true)
            return
        }
        work.attach(task)
    }

    final class Work: BackgroundDownload {
        let identifier: String
        var onExpire: (() -> Void)?
        var onRefused: (() -> Void)?
        private var task: BGContinuedProcessingTask?
        private var last: (downloaded: UInt64, total: UInt64)?
        private var result: Bool?

        init(identifier: String) {
            self.identifier = identifier
        }

        func attach(_ task: BGContinuedProcessingTask) {
            self.task = task
            // iOS calls this on a queue of its own: hop to the main actor.
            task.expirationHandler = { [weak self] in
                Task { @MainActor in self?.onExpire?() }
            }
            if let result {
                task.setTaskCompleted(success: result)
            } else if let last {
                update(downloaded: last.downloaded, total: last.total)
            }
        }

        func update(downloaded: UInt64, total: UInt64) {
            last = (downloaded, total)
            guard let task else { return }
            task.progress.totalUnitCount = Int64(clamping: max(total, 1))
            task.progress.completedUnitCount = Int64(clamping: min(downloaded, max(total, 1)))
            if total > 0 {
                task.updateTitle(task.title, subtitle: "\(Format.bytes(downloaded)) of \(Format.bytes(total))")
            }
        }

        func refused() {
            guard result == nil else { return }
            onRefused?()
        }

        func finish(success: Bool) {
            guard result == nil else { return }
            result = success
            task?.setTaskCompleted(success: success)
        }
    }
}

/// Does nothing: tests and previews.
final class NoBackgroundDownloads: BackgroundDownloadScheduler {
    func begin(model: String, title: String) -> (any BackgroundDownload)? { nil }
    func holdBriefly(active: Bool) {}
}
