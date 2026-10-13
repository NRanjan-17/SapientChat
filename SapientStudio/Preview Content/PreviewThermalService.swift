// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// `ThermalService` for SwiftUI previews: always reports a fixed state.
nonisolated struct PreviewThermalService: ThermalService {
    var pressure: ThermalPressure = .nominal

    func pressureUpdates() -> AsyncStream<ThermalPressure> {
        AsyncStream { continuation in
            continuation.yield(pressure)
        }
    }
}
