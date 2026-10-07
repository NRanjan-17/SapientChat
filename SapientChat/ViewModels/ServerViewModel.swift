import Foundation
import Observation
import UIKit

/// The local API server: `sapient serve`'s OpenAI-compatible endpoints,
/// served from this device on the same engine as the app.
/// Settings persist; the server keeps running while the app is in front.
///
/// iOS suspends apps in the background, so the server pauses there and
/// restarts when the app returns.
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

    /// `router` is shared with the URL handoff, so both see the same API key.
    init(router: ServeRouter, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.router = router
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
    }

    func stop() {
        wantsRunning = false
        server.stop()
        status = .stopped
        updateIdleTimer()
    }

    func clearLog() {
        log.removeAll()
    }

    func refreshAddresses() {
        addresses = NetworkAddresses.current()
    }

    /// Restarts a server the user left on, after iOS suspended it.
    func appDidBecomeActive() {
        refreshAddresses()
        if wantsRunning && status != .running { start() }
    }

    // MARK: Private

    private enum Keys {
        static let port = "server.port"
        static let allowsNetwork = "server.allowsNetwork"
        static let apiKey = "server.apiKey"
        static let keepsAwake = "server.keepsAwake"
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
