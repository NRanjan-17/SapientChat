// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// `MemoryService` for SwiftUI previews: fixed readings.
nonisolated struct PreviewMemoryService: MemoryService {
    var memory = MemoryStatus(footprintBytes: 900_000_000, availableBytes: 2_400_000_000)

    func status() -> MemoryStatus {
        memory
    }
}
