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
    static let logLimit = 100

    let id = UUID()
    private(set) var status: Status = .stopped
    private(set) var addresses: [NetworkAddresses.Address] = []
    /// Newest first, at most `logLimit`.
    private(set) var log: [ServeRouter.LogEntry] = []

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
    /// Required as `Authorization: Bearer <key>` when not empty.
    var apiKey: String {
        didSet {
            defaults.set(apiKey, forKey: Keys.apiKey)
            router.apiKey = apiKey
        }
    }
    /// Whether this build can keep the server running in the background.
    static let canRunInBackground: Bool = {
        #if SAPIENT_BACKGROUND_SERVER
        true
        #else
        false
        #endif
    }()

    /// Keep serving with the app in the background (silent audio, CPU only).
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
    @ObservationIgnored private let server = HTTPServer()
    @ObservationIgnored private let defaults: UserDefaults
    /// The user turned the server on (it may be paused in the background).
    @ObservationIgnored private var wantsRunning = false
    @ObservationIgnored private let keeper: any BackgroundKeeping
    @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

    /// `router` is shared with the URL handoff, so both see the same API key.
    init(router: ServeRouter, defaults: UserDefaults = .standard, keeper: (any BackgroundKeeping)? = nil) {
        self.defaults = defaults
        self.router = router
        self.keeper = keeper ?? Self.defaultKeeper()
        let runsInBackground = Self.canRunInBackground && defaults.bool(forKey: Keys.runsInBackground)
        self.runsInBackground = runsInBackground
        defaults.set(runsInBackground, forKey: EngineBackendPreference.cpuOnlyKey)
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

    /// Turns background serving on or off. Models in memory are released so
    /// they reload on the right hardware (CPU in the background, else GPU).
    func setRunsInBackground(_ on: Bool) {
        guard Self.canRunInBackground, on != runsInBackground else { return }
        runsInBackground = on
        backgroundError = nil
        defaults.set(on, forKey: Keys.runsInBackground)
        defaults.set(on, forKey: EngineBackendPreference.cpuOnlyKey)
        let router = router
        Task { await router.releaseAllModels() }
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
    }

    private static func defaultKeeper() -> any BackgroundKeeping {
        #if SAPIENT_BACKGROUND_SERVER
        SilentAudioKeeper()
        #else
        NoBackgroundKeeper()
        #endif
    }

    /// Silent audio runs only while the server is on with background mode on.
    private func updateKeeper() {
        if wantsRunning && runsInBackground {
            do {
                try keeper.start()
            } catch {
                backgroundError = "Couldn't keep running in the background: \(error.localizedDescription)"
                runsInBackground = false
                defaults.set(false, forKey: Keys.runsInBackground)
                defaults.set(false, forKey: EngineBackendPreference.cpuOnlyKey)
            }
        } else {
            keeper.stop()
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

    private func record(_ entry: ServeRouter.LogEntry) {
        log.insert(entry, at: 0)
        if log.count > Self.logLimit { log.removeLast(log.count - Self.logLimit) }
    }

    private func updateIdleTimer() {
        UIApplication.shared.isIdleTimerDisabled = wantsRunning && keepsAwake
    }
}
