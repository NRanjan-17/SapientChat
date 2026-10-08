// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import ActivityKit
import Foundation

/// The Live Activity shown in the Dynamic Island and on the Lock Screen
/// while SAPIENT works for another app or runs a benchmark. Shared by the
/// app (which starts and updates it) and the widget extension (which draws it).
nonisolated struct SapientActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Phase: String, Codable, Hashable, Sendable {
            case preparing, downloading, loading, generating, benchmarking, finished, failed
            /// The API server is up, waiting for or between requests.
            case serving
        }

        var phase: Phase
        /// A short line under the phase: "Run 2 of 5", "412 MB of 1.1 GB", an error.
        var detail: String?
        /// 0…1 for downloads and benchmark runs; nil when unknown.
        var progress: Double?
        var tokens: Int = 0
        /// Requests the server has answered since it started (server activity only).
        var requests: Int = 0
        /// How many models are downloading (downloads activity only).
        var downloadCount: Int = 0
        /// Combined download speed, bytes per second; nil until measured.
        var bytesPerSecond: Double?
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
        case .serving: "Serving"
        }
    }
}
