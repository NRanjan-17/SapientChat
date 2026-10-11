// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// The app's memory as the OS sees it.
nonisolated struct MemoryStatus: Equatable, Sendable {
    /// Current footprint: the number iOS compares against the app's limit.
    var footprintBytes: UInt64?
    /// Bytes the app can still allocate before iOS steps in, less the
    /// memory-mapped model files it holds (see `mappedBytes`). Nil when the
    /// platform enforces no limit (e.g. the simulator).
    var availableBytes: UInt64?
    /// Memory-mapped files resident in RAM: GGUF model weights. iOS leaves
    /// them out of the footprint, yet they fill the phone's RAM, and the
    /// phone runs out (jetsam "vm-pageshortage") before the app's own limit.
    var mappedBytes: UInt64?

    init(footprintBytes: UInt64?, availableBytes: UInt64?, mappedBytes: UInt64? = nil) {
        self.footprintBytes = footprintBytes
        self.availableBytes = availableBytes
        self.mappedBytes = mappedBytes
    }

    /// What the app really holds in RAM: footprint plus mapped model files.
    var residentBytes: UInt64? {
        footprintBytes.map { $0 + (mappedBytes ?? 0) }
    }

    static let unknown = MemoryStatus(footprintBytes: nil, availableBytes: nil)
}
