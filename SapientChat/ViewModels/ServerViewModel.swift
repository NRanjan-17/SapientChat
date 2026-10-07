import Foundation
import Observation
import UIKit

/// The local API server: `sapient serve`'s OpenAI-compatible endpoints,
/// served from this device on the same engine as the app.
/// Settings persist; the server keeps running while the app is in front.
///
/// iOS suspends apps in the background. By default the server gets iOS's
/// extra ~30 s to finish what's running, then pauses until the app
/// returns. With "Keep running in background" (Debug/sideload builds only)
/// a silent audio session keeps the app alive and models run on the CPU.
@Observable
final class ServerViewModel: Identifiable {
    enum Status: Equatable {
        case stopped
        case starting
        case running
        case failed(String)
    }

    static let defaultPort: UInt16 = 11435
    /// Requests kept in the log, across launches.
    static let logLimit = 500

    let id = UUID()
    private(set) var status: Status = .stopped
    private(set) var addresses: [NetworkAddresses.Address] = []
    /// Newest first, at most `logLimit`.
    private(set) var log: [RequestLogEntry] = []

    /// One-line server state for toggles and lists.
    var statusTitle: String {
        switch status {
        case .stopped: "Server off"
        case .starting: "Starting…"
        case .running: "Running"
        case .failed: "Couldn't start"
        }
    }

    var port: UInt16 {
        didSet { settingChanged(Keys.port, Int(port)) }
    }
    /// Reachable from other devices on the network, not just this one.
    var allowsNetwork: Bool {
        didSet { settingChanged(Keys.allowsNetwork, allowsNetwork) }
    }
    /// Save each request's prompt, reply and bodies in the log, not just
    /// what happened. On by default; everything stays on this device.
    var savesContent: Bool {
        didSet { defaults.set(savesContent, forKey: Keys.savesContent) }
    }
    /// Required as `Authorization: Bearer <key>` when not empty.
    var apiKey: String {
        didSet {
            defaults.set(apiKey, forKey: Keys.apiKey)
            router.apiKey = apiKey
        }
    }
    /// Whether this build can keep the server running in the background.
    nonisolated static let canRunInBackground: Bool = {
        #if SAPIENT_BACKGROUND_SERVER
        true
        #else
        false
        #endif
    }()

    /// The user's choice to keep serving with the app in the background.
    /// It applies only while the server is on (`isServingInBackground`).
    private(set) var runsInBackground: Bool
    /// Why background mode couldn't start, if it failed.
    private(set) var backgroundError: String?

    /// Stops the screen locking (which would pause the server) while running.
    var keepsAwake: Bool {
        didSet {
            defaults.set(keepsAwake, forKey: Keys.keepsAwake)
            updateIdleTimer()
        }
    }

    @ObservationIgnored private let router: ServeRouter
    @ObservationIgnored private let requestLog: any RequestLogStore
    @ObservationIgnored private let server = HTTPServer()
    @ObservationIgnored private let defaults: UserDefaults
    /// The user turned the server on (it may be paused in the background).
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private let keeper: any BackgroundKeeping
    /// Keeper starts and stops run one after another, in the order asked.
    @ObservationIgnored private var keeperTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    /// The Dynamic Island while serving in the background.
    @ObservationIgnored let serverActivity: ServerLiveActivity

    /// `router` is shared with the URL handoff, so both see the same API key.
    init(
        router: ServeRouter,
        defaults: UserDefaults = .standard,
        keeper: (any BackgroundKeeping)? = nil,
        liveActivities: any LiveActivityService = NoLiveActivities(),
        requestLog: any RequestLogStore = InMemoryRequestLogStore()
    ) {
        self.defaults = defaults
        self.router = router
        self.requestLog = requestLog
        log = requestLog.entries(limit: Self.logLimit)
        savesContent = defaults.object(forKey: Keys.savesContent) as? Bool ?? true
        serverActivity = ServerLiveActivity(service: liveActivities)
        // Request trackers update the server's activity while it's up, and
        // start their own otherwise.
        router.liveActivities = serverActivity
        self.keeper = keeper ?? Self.defaultKeeper()
        runsInBackground = Self.canRunInBackground && defaults.bool(forKey: Keys.runsInBackground)
        // The server starts off, so the app starts as a normal app: GPU models.
        defaults.set(false, forKey: EngineBackendPreference.cpuOnlyKey)
        let savedPort = defaults.integer(forKey: Keys.port)
        port = (1...Int(UInt16.max)).contains(savedPort) ? UInt16(savedPort) : Self.defaultPort
        allowsNetwork = defaults.object(forKey: Keys.allowsNetwork) as? Bool ?? true
        apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        keepsAwake = defaults.object(forKey: Keys.keepsAwake) as? Bool ?? true
        router.apiKey = apiKey
        router.onRequest = { [weak self] entry in self?.record(entry) }
    }

    var isOn: Bool {
        get { wantsRunning }
        set { newValue ? start() : stop() }
    }

    /// The server is on and set to keep running in the background. Only then
    /// does anything keep the app alive; otherwise it closes like any app.
    var isServingInBackground: Bool {
        wantsRunning && runsInBackground
    }

    /// Catalog models, for the Try It commands.
    var models: [PhoneModel] {
        router.catalogModels()
    }

    /// Base URLs clients can use, e.g. `http://192.168.1.20:11435`.
    var endpoints: [(label: String, url: String)] {
        var list = [(label: "This device", url: "http://127.0.0.1:\(port)")]
        if allowsNetwork {
            list += addresses.map { (label: $0.label, url: "http://\($0.ip):\(port)") }
        }
        return list
    }

    func start() {
        wantsRunning = true
        status = .starting
        refreshAddresses()
        let router = router
        server.start(
            HTTPServer.Configuration(port: port, allowsNetwork: allowsNetwork, bonjourName: allowsNetwork ? Self.bonjourName : nil),
            handler: { request in await router.handle(request) },
            onState: { [weak self] state in
                Task { @MainActor [weak self] in self?.apply(state) }
            }
        )
        updateIdleTimer()
        updateKeeper()
    }

    func stop() {
        wantsRunning = false
        server.stop()
        status = .stopped
        updateIdleTimer()
        updateKeeper()
    }

    /// Saves the background choice; it takes effect while the server is on.
    func setRunsInBackground(_ on: Bool) {
        guard Self.canRunInBackground, on != runsInBackground else { return }
        runsInBackground = on
        backgroundError = nil
        defaults.set(on, forKey: Keys.runsInBackground)
        updateKeeper()
    }

    /// Leaving the app: with background mode off, ask iOS for its extra time
    /// so requests already running can finish before the server pauses.
    func appDidLeaveForeground() {
        guard wantsRunning, !runsInBackground, backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Finish API requests") { [weak self] in
            self?.endBackgroundTask()
        }
    }

    func clearLog() {
        log.removeAll()
        requestLog.deleteAll()
    }

    func refreshAddresses() {
        addresses = NetworkAddresses.current()
    }

    /// Restarts a server the user left on, after iOS suspended it.
    func appDidBecomeActive() {
        endBackgroundTask()
        refreshAddresses()
        if wantsRunning && status != .running { start() }
    }

    // MARK: Private

    private enum Keys {
        static let port = "server.port"
        static let allowsNetwork = "server.allowsNetwork"
        static let apiKey = "server.apiKey"
        static let keepsAwake = "server.keepsAwake"
        static let runsInBackground = "server.runsInBackground"
        static let savesContent = "server.savesContent"
    }

    private static func defaultKeeper() -> any BackgroundKeeping {
        #if SAPIENT_BACKGROUND_SERVER
        SilentAudioKeeper()
        #else
        NoBackgroundKeeper()
        #endif
    }

    /// Silent audio, CPU-only models and the server's Dynamic Island run
    /// only while serving in the background. Otherwise all three are off, so
    /// the app suspends and closes normally.
    private func updateKeeper() {
        defer {
            updateEngineBackend()
            updateServerActivity()
        }
        let wantsKeeper = isServingInBackground
        let keeper = keeper
        let previous = keeperTask
        keeperTask = Task { [weak self] in
            await previous?.value
            guard wantsKeeper else { return await keeper.stop() }
            do {
                try await keeper.start()
            } catch {
                self?.keeperFailed(error)
            }
        }
    }

    private func keeperFailed(_ error: any Error) {
        backgroundError = "Couldn't keep running in the background: \(error.localizedDescription)"
        runsInBackground = false
        defaults.set(false, forKey: Keys.runsInBackground)
        updateKeeper()
    }

    /// Waits for keeper starts and stops already asked for (for tests).
    func keeperSettled() async {
        await keeperTask?.value
    }

    /// CPU while serving in the background (iOS allows no GPU work there),
    /// GPU otherwise. Loaded models are released when it changes, so they
    /// reload on the right one.
    private func updateEngineBackend() {
        let cpuOnly = isServingInBackground
        guard cpuOnly != EngineBackendPreference.cpuOnly(defaults) else { return }
        defaults.set(cpuOnly, forKey: EngineBackendPreference.cpuOnlyKey)
        let router = router
        Task { await router.releaseAllModels() }
    }

    private func updateServerActivity() {
        if isServingInBackground {
            serverActivity.begin(endpoint: endpoints.last.map { $0.url.replacing("http://", with: "") } ?? "port \(port)")
        } else {
            serverActivity.finish()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    private static var bonjourName: String {
        "SapientChat on \(UIDevice.current.name)"
    }

    /// Port and reachability apply on restart.
    private func settingChanged(_ key: String, _ value: Any) {
        defaults.set(value, forKey: key)
        if wantsRunning { start() }
    }

    private func apply(_ state: HTTPServer.State) {
        // Ignore a late `stopped` from the listener a restart replaced.
        guard wantsRunning || state == .stopped else { return }
        status = switch state {
        case .stopped: wantsRunning ? .starting : .stopped
        case .starting: .starting
        case .running: .running
        case .failed(let message): .failed(message)
        }
        updateIdleTimer()
    }

    private func record(_ entry: RequestLogEntry) {
        serverActivity.recorded(method: entry.method, path: entry.path, status: entry.status)
        let saved = savesContent ? entry : entry.withoutContent()
        log.insert(saved, at: 0)
        requestLog.insert(saved)
        if log.count > Self.logLimit {
            log.removeLast(log.count - Self.logLimit)
            requestLog.trim(keeping: Self.logLimit)
        }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = wantsRunning && keepsAwake
    }
}
