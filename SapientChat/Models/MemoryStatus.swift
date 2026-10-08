// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// The app's memory as the OS sees it.
nonisolated struct MemoryStatus: Equatable, Sendable {
    /// Current footprint: the number iOS compares against the app's limit.
    var footprintBytes: UInt64?
    /// Bytes the app can still allocate before iOS steps in. Nil when the
    /// platform enforces no limit (e.g. the simulator).
    var availableBytes: UInt64?

    static let unknown = MemoryStatus(footprintBytes: nil, availableBytes: nil)
}
