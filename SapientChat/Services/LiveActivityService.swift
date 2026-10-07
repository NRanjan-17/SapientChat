import ActivityKit
import Foundation

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
final class ActivityKitLiveActivities: LiveActivityService {
    private var activities: [UUID: Activity<SapientActivityAttributes>] = [:]
    /// How long a finished activity stays before it goes away.
    private let lingering: Duration = .seconds(4)

    func start(_ attributes: SapientActivityAttributes, state: SapientActivityAttributes.ContentState) -> UUID? {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return nil }
        do {
            let activity = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: nil))
            let id = UUID()
            activities[id] = activity
            return id
        } catch {
            return nil
        }
    }

    func update(_ id: UUID, state: SapientActivityAttributes.ContentState) {
        guard let activity = activities[id] else { return }
        Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
    }

    func end(_ id: UUID, state: SapientActivityAttributes.ContentState) {
        guard let activity = activities.removeValue(forKey: id) else { return }
        let dismissal = Date.now.addingTimeInterval(TimeInterval(lingering.components.seconds))
        Task { await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .after(dismissal)) }
    }
}

/// Does nothing; the default where no Island is wanted (tests, previews).
final class NoLiveActivities: LiveActivityService {
    func start(_ attributes: SapientActivityAttributes, state: SapientActivityAttributes.ContentState) -> UUID? { nil }
    func update(_ id: UUID, state: SapientActivityAttributes.ContentState) {}
    func end(_ id: UUID, state: SapientActivityAttributes.ContentState) {}
}
