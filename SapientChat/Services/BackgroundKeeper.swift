import AVFoundation
import Foundation

/// Keeps the app running in the background so the API server can answer,
/// by playing silence through the background audio mode. Only compiled
/// into builds with `SAPIENT_BACKGROUND_SERVER` (Debug/sideload): Apple
/// rejects App Store apps that use background audio for anything else.
nonisolated protocol BackgroundKeeping: AnyObject, Sendable {
    var isRunning: Bool { get }
    func start() async throws
    func stop() async
}

/// All audio work runs on the keeper's own serial queue, never the main
/// thread: AVAudioSession calls can block, and on the main thread that
/// freezes the UI (Xcode's "AVAudioSession Hang Risk").
nonisolated final class SilentAudioKeeper: BackgroundKeeping, @unchecked Sendable {
    private let queue = DispatchQueue(label: "SapientChat.SilentAudioKeeper")
    // Everything below is touched only on `queue`.
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var interruptionObserver: NSObjectProtocol?
    private var running = false

    var isRunning: Bool { queue.sync { running } }

    func start() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            queue.async { [self] in
                do {
                    try startOnQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func stop() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            queue.async { [self] in
                stopOnQueue()
                continuation.resume()
            }
        }
    }

    private func startOnQueue() throws {
        guard !running else { return }
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
        running = true
        observeInterruptions()
    }

    private func stopOnQueue() {
        guard running else { return }
        running = false
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
            forName: AVAudioSession.resumptionRecommendationNotification, object: nil, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.resumeOnQueue() }
        }
    }

    private func resumeOnQueue() {
        guard running else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { try? engine.start() }
        try? player.playAudio()
    }

    enum KeeperError: Error { case noBuffer }
}

/// Builds without the background mode; nothing runs.
nonisolated final class NoBackgroundKeeper: BackgroundKeeping {
    var isRunning: Bool { false }
    func start() async throws {}
    func stop() async {}
}
