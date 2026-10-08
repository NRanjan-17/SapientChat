// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Sapient

/// `MemoryService` backed by SAPIENT's readings: iOS `phys_footprint` (what
/// the per-app memory limit is enforced against) and
/// `os_proc_available_memory`.
nonisolated struct SapientMemoryService: MemoryService {
    func status() -> MemoryStatus {
        MemoryStatus(footprintBytes: memoryFootprintBytes(), availableBytes: availableMemoryBytes())
    }
}
