// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Reports the device's thermal state.
nonisolated protocol ThermalService: Sendable {
    /// Yields the current state immediately, then every change, until the
    /// consuming task is cancelled.
    func pressureUpdates() -> AsyncStream<ThermalPressure>
}
