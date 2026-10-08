// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// One Live Activity for all model downloads, listing each model with its
/// progress. The Dynamic Island shows one activity at a time, so one per
/// download hid all but one of them. Shown when iOS isn't already showing
/// the downloads' progress itself (its continued processing task).
final class DownloadsLiveActivity {
    typealias State = SapientActivityAttributes.ContentState
    typealias Item = SapientActivityAttributes.DownloadItem

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

    /// Shows `items` (starting the activity if needed). A model joining or
    /// leaving is sent at once; progress at most about once a second.
    func show(_ items: [Item], progress: Double?) {
        let listChanged = items.map(\.name) != state.downloads.map(\.name)
        state.phase = .downloading
        state.downloads = items
        state.progress = progress
        state.detail = items.count == 1 ? items[0].name : "\(items.count) models"
        let now = clock()
        guard let id else {
            state.startedAt = now
            id = service.start(SapientActivityAttributes(title: "Downloads", model: "Models"), state: state)
            lastSent = now
            return
        }
        guard listChanged || now.timeIntervalSince(lastSent) >= minimumInterval else { return }
        lastSent = now
        service.update(id, state: state)
    }

    /// Ends it once every download is over.
    func finish(failures: [String]) {
        guard let id else { return }
        self.id = nil
        state.downloads = []
        state.progress = nil
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
