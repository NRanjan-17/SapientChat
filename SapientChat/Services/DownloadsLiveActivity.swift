// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// One Live Activity for all model downloads: how many, their combined
/// progress and download speed (no per-model list). The Dynamic Island
/// shows one activity at a time, so one per download hid all but one.
/// Shown when iOS isn't already showing the downloads' progress itself
/// (its continued processing task).
final class DownloadsLiveActivity {
    typealias State = SapientActivityAttributes.ContentState

    private let service: any LiveActivityService
    private let minimumInterval: TimeInterval
    private let clock: () -> Date
    private var id: UUID?
    private(set) var state: State
    private var lastSent = Date.distantPast

    init(service: any LiveActivityService, minimumInterval: TimeInterval = 1, clock: @escaping () -> Date = { .now }) {
        self.service = service
        self.minimumInterval = minimumInterval
        self.clock = clock
        state = State(phase: .downloading, startedAt: clock())
    }

    var isActive: Bool { id != nil }

    /// `names` are the models downloading (one name is shown; more show as
    /// a count). The count changing is sent at once; progress and speed at
    /// most about once a second.
    func show(names: [String], progress: Double?, bytesPerSecond: Double?) {
        let countChanged = names.count != state.downloadCount
        state.phase = .downloading
        state.downloadCount = names.count
        state.progress = progress
        state.bytesPerSecond = bytesPerSecond
        // Speed goes in the status line: the Island has no room for more.
        let what = names.count == 1 ? names[0] : "\(names.count) models"
        state.detail = bytesPerSecond.map { "\(what) · \(Format.bytes(UInt64($0)))/s" } ?? what
        let now = clock()
        guard let id else {
            state.startedAt = now
            id = service.start(SapientActivityAttributes(title: "Sapient", model: "Model downloads"), state: state)
            lastSent = now
            return
        }
        guard countChanged || now.timeIntervalSince(lastSent) >= minimumInterval else { return }
        lastSent = now
        service.update(id, state: state)
    }

    /// Ends it once every download is over.
    func finish(failures: [String]) {
        guard let id else { return }
        self.id = nil
        state.downloadCount = 0
        state.progress = nil
        state.bytesPerSecond = nil
        state.endedAt = clock()
        if failures.isEmpty {
            state.phase = .finished
            state.detail = "Downloaded"
        } else {
            state.phase = .failed
            state.detail = "Failed: " + failures.joined(separator: ", ")
        }
        service.end(id, state: state)
    }
}
