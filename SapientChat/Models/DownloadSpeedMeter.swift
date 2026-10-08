// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Download speed over the last few seconds of progress, so one slow or
/// fast update doesn't make the number jump.
nonisolated struct DownloadSpeedMeter {
    /// How far back speed is averaged.
    var window: Duration = .seconds(3)
    private var samples: [(time: ContinuousClock.Instant, bytes: UInt64)] = []

    /// Records `bytes` received so far; returns bytes per second, or nil
    /// until there's half a second of history to measure.
    mutating func record(_ bytes: UInt64, at time: ContinuousClock.Instant = .now) -> Double? {
        // Fewer bytes than before: the download restarted.
        if let last = samples.last, bytes < last.bytes { samples.removeAll() }
        samples.append((time, bytes))
        while samples.count > 2, time - samples[1].time >= window {
            samples.removeFirst()
        }
        guard let first = samples.first else { return nil }
        let elapsed = time - first.time
        guard elapsed >= .milliseconds(500) else { return nil }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        return Double(bytes - first.bytes) / seconds
    }
}
