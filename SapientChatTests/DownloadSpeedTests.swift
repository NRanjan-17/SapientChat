// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Testing
@testable import SapientChat

struct DownloadSpeedTests {
    @Test func measuresOverTheRecentWindow() {
        var meter = DownloadSpeedMeter()
        let start = ContinuousClock.now
        #expect(meter.record(0, at: start) == nil)
        #expect(meter.record(1_000_000, at: start + .milliseconds(250)) == nil, "too soon to measure")
        let speed = meter.record(2_000_000, at: start + .seconds(1))
        #expect(speed == 2_000_000)
        // Old samples drop out: only the last ~3 s count.
        _ = meter.record(3_000_000, at: start + .seconds(4))
        let recent = meter.record(4_000_000, at: start + .seconds(5))
        #expect(recent.map { abs($0 - 500_000) < 1 } == true)
    }

    @Test func restartsWhenTheDownloadDoes() {
        var meter = DownloadSpeedMeter()
        let start = ContinuousClock.now
        _ = meter.record(5_000_000, at: start)
        #expect(meter.record(100, at: start + .seconds(1)) == nil)
    }

    @Test func progressShowsSpeedAndTimeLeft() {
        var progress = DownloadProgress(downloadedBytes: 400_000_000, totalBytes: 1_000_000_000)
        #expect(progress.speedText == nil && progress.remainingText == nil)
        progress.bytesPerSecond = 10_000_000
        #expect(progress.secondsRemaining == 60)
        #expect(progress.speedText?.hasSuffix("/s") == true)
        #expect(progress.remainingText?.hasSuffix(" left") == true)
    }
}
