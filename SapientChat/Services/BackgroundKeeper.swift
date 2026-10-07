import AVFoundation
import Foundation

/// Keeps the app running in the background so the API server can answer,
/// by playing silence through the background audio mode. Only compiled
/// into builds with `SAPIENT_BACKGROUND_SERVER` (Debug/sideload): Apple
/// rejects App Store apps that use background audio for anything else.
protocol BackgroundKeeping: AnyObject {
    var isRunning: Bool { get }
    func start() throws
    func stop()
}

final class SilentAudioKeeper: BackgroundKeeping {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var interruptionObserver: NSObjectProtocol?
    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        // Mixes with other audio, so music and calls carry on as usual.
        try session.setCategory(.playback, options: [.mixWithOthers])
        try session.setActive(true)
        let format = engine.outputNode.inputFormat(forBus: 0)
        guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(format.sampleRate)) else {
            throw KeeperError.noBuffer
        }
        silence.frameLength = silence.frameCapacity // zero-filled: silence
        engine.attach(player)
        try engine.connectNode(player, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.scheduleBuffer(silence, at: nil, options: .loops)
        try player.playAudio()
        isRunning = true
        observeInterruptions()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let interruptionObserver { NotificationCenter.default.removeObserver(interruptionObserver) }
        interruptionObserver = nil
        player.stop()
        engine.stop()
        engine.detach(player)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// A call or another app's audio can stop ours. When iOS says the
    /// interruption is over, resume, whatever its recommendation: the
    /// silence mixes with other audio, so resuming never cuts anyone off.
    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                try? AVAudioSession.sharedInstance().setActive(true)
                if !self.engine.isRunning { try? self.engine.start() }
                try? self.player.playAudio()
            }
        }
    }

    enum KeeperError: Error { case noBuffer }
}

/// Builds without the background mode; nothing runs.
final class NoBackgroundKeeper: BackgroundKeeping {
    var isRunning: Bool { false }
    func start() throws {}
    func stop() {}
}

/// Whether models load on the CPU. On while the server runs in the
/// background: iOS doesn't allow GPU work from a background app.
nonisolated enum EngineBackendPreference {
    static let cpuOnlyKey = "engine.cpuOnly"

    static func cpuOnly(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: cpuOnlyKey)
    }
}
