// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Reads the app's memory as the OS sees it.
nonisolated protocol MemoryService: Sendable {
    func status() -> MemoryStatus
}
