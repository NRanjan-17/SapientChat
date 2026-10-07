import ActivityKit
import Foundation

/// The Live Activity shown in the Dynamic Island and on the Lock Screen
/// while SAPIENT works for another app or runs a benchmark. Shared by the
/// app (which starts and updates it) and the widget extension (which draws it).
nonisolated struct SapientActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Phase: String, Codable, Hashable, Sendable {
            case preparing, downloading, loading, generating, benchmarking, finished, failed
        }

        var phase: Phase
        /// A short line under the phase: "Run 2 of 5", "412 MB of 1.1 GB", an error.
        var detail: String?
        /// 0…1 for downloads and benchmark runs; nil when unknown.
        var progress: Double?
        var tokens: Int = 0
        var tokensPerSecond: Double?
        var timeToFirstTokenMs: Int?
        var startedAt: Date
        /// Set once the work is over, so the elapsed time stops.
        var endedAt: Date?

        var isOver: Bool { phase == .finished || phase == .failed }
    }

    /// Who asked: "Request from Shortcuts", "API request", "Benchmark".
    var title: String
    /// The model's display name.
    var model: String
}

extension SapientActivityAttributes.ContentState.Phase {
    var label: String {
        switch self {
        case .preparing: "Preparing"
        case .downloading: "Downloading"
        case .loading: "Loading into memory"
        case .generating: "Generating"
        case .benchmarking: "Benchmarking"
        case .finished: "Done"
        case .failed: "Failed"
        }
    }
}
