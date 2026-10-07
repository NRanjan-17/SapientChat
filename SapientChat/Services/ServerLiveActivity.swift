import Foundation

/// The API server's own Live Activity, shown while the server runs with
/// background mode on. iOS lets an app start a Live Activity only from
/// the foreground, but update one from the background, so this one is
/// started when serving begins and every request then updates it: a ping
/// bumps the count, and a chat shows its model and speed while it runs.
///
/// It stands in for the Dynamic Island service while active: request
/// trackers that would start their own activity update this one instead,
/// and their "end" returns it to Serving with a summary.
final class ServerLiveActivity: LiveActivityService {
    typealias State = SapientActivityAttributes.ContentState

    private let service: any LiveActivityService
    private let clock: () -> Date
    private let minimumInterval: TimeInterval
    private var id: UUID?
    private(set) var state: State
    /// The model of the request now running, shown in the detail line.
    private var currentModel: String?
    private var lastSent = Date.distantPast
    private var pending: Task<Void, Never>?
    /// Re-sends the state now and then, so the activity's stale date keeps
    /// moving while the server is idle (a dead app's activity goes stale).
    private let heartbeatInterval: Duration
    private var heartbeat: Task<Void, Never>?

    init(
        service: any LiveActivityService,
        minimumInterval: TimeInterval = 1,
        heartbeatInterval: Duration = .seconds(30),
        clock: @escaping () -> Date = { .now }
    ) {
        self.service = service
        self.clock = clock
        self.minimumInterval = minimumInterval
        self.heartbeatInterval = heartbeatInterval
        state = State(phase: .serving, detail: "Waiting for requests", startedAt: clock())
    }

    var isActive: Bool { id != nil }

    /// Starts the activity; `endpoint` is the address shown under the title.
    func begin(endpoint: String) {
        guard id == nil else { return }
        state = State(phase: .serving, detail: "Waiting for requests", startedAt: clock())
        id = service.start(SapientActivityAttributes(title: "API server", model: endpoint), state: state)
        lastSent = clock()
        guard id != nil else { return }
        let interval = heartbeatInterval
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                self?.send(force: true)
            }
        }
    }

    /// Ends it, e.g. when the server or background mode is turned off.
    func finish() {
        pending?.cancel()
        pending = nil
        heartbeat?.cancel()
        heartbeat = nil
        guard let id else { return }
        self.id = nil
        var final = state
        final.phase = .finished
        final.detail = "Server stopped"
        final.endedAt = clock()
        service.end(id, state: final)
    }

    /// Any request the server answered (pings included).
    func recorded(method: String, path: String, status: Int) {
        guard id != nil else { return }
        state.requests += 1
        if state.phase == .serving {
            state.detail = "Last: \(method) \(path)" + (status >= 400 ? " · \(status)" : "")
        }
        send()
    }

    // MARK: LiveActivityService (request trackers)

    func start(_ attributes: SapientActivityAttributes, state: State) -> UUID? {
        guard let id else { return service.start(attributes, state: state) }
        currentModel = attributes.model
        show(state)
        return id
    }

    func update(_ requestID: UUID, state: State) {
        guard requestID == id else { return service.update(requestID, state: state) }
        show(state)
    }

    func end(_ requestID: UUID, state: State) {
        guard requestID == id else { return service.end(requestID, state: state) }
        let model = currentModel ?? "Request"
        currentModel = nil
        self.state.phase = .serving
        self.state.progress = nil
        self.state.detail = state.phase == .failed
            ? "Last: \(model) failed"
            : "Last: \(model)" + (state.tokens > 0 ? " · \(state.tokens) tokens" : "")
        if let rate = state.tokensPerSecond { self.state.tokensPerSecond = rate }
        send(force: true)
    }

    // MARK: Private

    /// Mirrors a request's progress, keeping the server's own fields.
    private func show(_ request: State) {
        state.phase = request.phase
        state.progress = request.progress
        state.tokens = request.tokens
        state.tokensPerSecond = request.tokensPerSecond ?? state.tokensPerSecond
        state.timeToFirstTokenMs = request.timeToFirstTokenMs
        state.detail = [currentModel, request.detail].compactMap(\.self).joined(separator: " · ")
        send()
    }

    /// At most about once a second; a skipped update is sent when the
    /// interval is up, so the last state always shows.
    private func send(force: Bool = false) {
        guard let id else { return }
        let now = clock()
        let wait = minimumInterval - now.timeIntervalSince(lastSent)
        if force || wait <= 0 {
            pending?.cancel()
            pending = nil
            lastSent = now
            service.update(id, state: state)
        } else if pending == nil {
            pending = Task { [weak self] in
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled, let self else { return }
                self.pending = nil
                self.send(force: true)
            }
        }
    }
}
