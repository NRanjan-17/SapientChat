// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import ActivityKit
import Foundation
import OSLog

/// Starts, updates and ends SAPIENT's Live Activity (the Dynamic Island).
/// Behind a protocol so tests can record calls instead.
protocol LiveActivityService: AnyObject {
    /// Starts one; nil when Live Activities are off or iOS refuses (the app
    /// can only start one while it's in the foreground).
    func start(_ attributes: SapientActivityAttributes, state: SapientActivityAttributes.ContentState) -> UUID?
    func update(_ id: UUID, state: SapientActivityAttributes.ContentState)
    /// Shows the final state for a few seconds, then removes it.
    func end(_ id: UUID, state: SapientActivityAttributes.ContentState)
}

/// The real one, backed by ActivityKit.
///
/// A process that dies (Xcode reinstall, iOS ending it in the background)
/// can't end its activities, and the next launch doesn't know them, so they
/// would sit on screen frozen. So: leftovers are ended at launch, and every
/// update carries a stale date, after which iOS shows the activity as out
/// of date instead of as live.
final class ActivityKitLiveActivities: LiveActivityService {
    /// Kept up to date by updates (the server's heartbeat does it while idle).
    static let staleAfter: TimeInterval = 120

    private var activities: [UUID: Activity<SapientActivityAttributes>] = [:]
    /// How long a finished activity stays before it goes away.
    private let lingering: Duration = .seconds(4)
    private let log = Logger(subsystem: "SapientChat", category: "LiveActivity")

    init() {
        endLeftovers()
    }

    func start(_ attributes: SapientActivityAttributes, state: SapientActivityAttributes.ContentState) -> UUID? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log.info("Not started: Live Activities are off")
            return nil
        }
        do {
            let activity = try Activity.request(attributes: attributes, content: content(state))
            let id = UUID()
            activities[id] = activity
            log.info("Started \(activity.id, privacy: .public): \(attributes.title, privacy: .public)")
            return id
        } catch {
            log.error("Couldn't start: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func update(_ id: UUID, state: SapientActivityAttributes.ContentState) {
        guard let activity = activities[id] else { return }
        log.debug("Update \(activity.id, privacy: .public): \(state.phase.rawValue, privacy: .public), \(state.tokens) tokens, \(state.requests) requests")
        let content = content(state)
        Task { await activity.update(content) }
    }

    func end(_ id: UUID, state: SapientActivityAttributes.ContentState) {
        guard let activity = activities.removeValue(forKey: id) else { return }
        log.info("End \(activity.id, privacy: .public): \(state.phase.rawValue, privacy: .public)")
        let dismissal = Date.now.addingTimeInterval(TimeInterval(lingering.components.seconds))
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(dismissal)) }
    }

    private func content(_ state: SapientActivityAttributes.ContentState) -> ActivityContent<SapientActivityAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(Self.staleAfter))
    }

    /// Ends activities left by an earlier run of the app.
    private func endLeftovers() {
        let leftovers = Activity<SapientActivityAttributes>.activities
        guard !leftovers.isEmpty else { return }
        log.info("Ending \(leftovers.count) left over from an earlier run")
        for activity in leftovers {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}

/// Does nothing; the default where no Island is wanted (tests, previews).
final class NoLiveActivities: LiveActivityService {
    func start(_ attributes: SapientActivityAttributes, state: SapientActivityAttributes.ContentState) -> UUID? { nil }
    func update(_ id: UUID, state: SapientActivityAttributes.ContentState) {}
    func end(_ id: UUID, state: SapientActivityAttributes.ContentState) {}
}
