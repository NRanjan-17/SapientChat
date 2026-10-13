// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// Keeps the app's current activity where code can read it. ActivityKit
/// only draws Live Activities; it doesn't say what they show. A Mac has no
/// Dynamic Island, and Live Activities aren't offered to an iPad app
/// running on one, so the notch helper (Sapient Island, a small Mac app)
/// asks the server instead: `GET /v1/activity` answers from here.
///
/// It sits in front of the real service: every call is recorded and passed
/// on, so on iPhone the real Island works exactly as before.
@Observable
final class WindowIsland: LiveActivityService {
    struct Item: Identifiable, Equatable {
        let id: UUID
        let attributes: SapientActivityAttributes
        var state: SapientActivityAttributes.ContentState
        /// Bumped on every change, to pick the one to show.
        var touched: Int

        static func == (lhs: Item, rhs: Item) -> Bool {
            lhs.id == rhs.id && lhs.state == rhs.state && lhs.touched == rhs.touched
        }
    }

    /// Activities running now, and ones that just ended (kept a moment).
    private(set) var items: [Item] = []

    @ObservationIgnored private let inner: any LiveActivityService
    /// Our id → the real activity's, when the real service started one.
    @ObservationIgnored private var innerIDs: [UUID: UUID] = [:]
    @ObservationIgnored private var counter = 0
    /// How long a finished activity stays before it goes away.
    @ObservationIgnored private let lingering: Duration

    init(inner: any LiveActivityService = NoLiveActivities(), lingering: Duration = .seconds(4)) {
        self.inner = inner
        self.lingering = lingering
    }

    /// The one to show: the activity that changed last, work still running
    /// before work that's over.
    var current: Item? {
        items.max { lhs, rhs in
            if lhs.state.isOver != rhs.state.isOver { return lhs.state.isOver }
            return lhs.touched < rhs.touched
        }
    }

    /// The current activity for `GET /v1/activity`; inactive when there is none.
    var snapshot: ActivitySnapshot {
        guard let item = current else { return .inactive }
        let state = item.state
        return ActivitySnapshot(
            active: true, title: item.attributes.title, model: item.attributes.model,
            phase: state.phase.rawValue, label: state.phase.label, detail: state.detail,
            progress: state.isOver ? nil : state.progress, tokens: state.tokens,
            tokensPerSecond: state.tokensPerSecond, timeToFirstTokenMs: state.timeToFirstTokenMs,
            requests: state.requests, startedAt: state.startedAt.timeIntervalSince1970,
            endedAt: state.endedAt?.timeIntervalSince1970
        )
    }

    func start(_ attributes: SapientActivityAttributes, state: SapientActivityAttributes.ContentState) -> UUID? {
        let id = UUID()
        if let real = inner.start(attributes, state: state) { innerIDs[id] = real }
        counter += 1
        items.append(Item(id: id, attributes: attributes, state: state, touched: counter))
        return id
    }

    func update(_ id: UUID, state: SapientActivityAttributes.ContentState) {
        if let real = innerIDs[id] { inner.update(real, state: state) }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        counter += 1
        items[index].state = state
        items[index].touched = counter
    }

    func end(_ id: UUID, state: SapientActivityAttributes.ContentState) {
        if let real = innerIDs.removeValue(forKey: id) { inner.end(real, state: state) }
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        counter += 1
        items[index].state = state
        items[index].touched = counter
        Task { [weak self, lingering] in
            try? await Task.sleep(for: lingering)
            self?.items.removeAll { $0.id == id }
        }
    }
}

/// `GET /v1/activity`: what Sapient is doing right now, as the Dynamic
/// Island would show it. Times are seconds since 1970.
nonisolated struct ActivitySnapshot: Codable, Equatable, Sendable {
    /// False when nothing is running; the other fields are then empty.
    var active: Bool
    /// Who asked: "API server", "Request from Shortcuts", "Benchmark".
    var title: String?
    /// The model's name, or the server's address for the server's activity.
    var model: String?
    /// "serving", "generating", "downloading", "loading", "benchmarking",
    /// "paused", "preparing", "finished" or "failed".
    var phase: String?
    /// The phase for people: "Serving", "Generating".
    var label: String?
    var detail: String?
    /// 0…1 for downloads and benchmarks.
    var progress: Double?
    var tokens: Int?
    var tokensPerSecond: Double?
    var timeToFirstTokenMs: Int?
    /// Requests answered since the server started.
    var requests: Int?
    var startedAt: Double?
    var endedAt: Double?

    static let inactive = ActivitySnapshot(active: false)
}
