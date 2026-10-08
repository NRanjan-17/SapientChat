// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// App-wide device state shared by every screen: memory as iOS sees it and
/// the thermal state (which is also fed to the engine).
@Observable
final class DeviceStatus {
    private(set) var memory: MemoryStatus
    private(set) var thermal: ThermalPressure = .nominal

    @ObservationIgnored private let memoryService: any MemoryService
    @ObservationIgnored private let thermalService: any ThermalService

    init(memoryService: any MemoryService, thermalService: any ThermalService) {
        self.memoryService = memoryService
        self.thermalService = thermalService
        memory = memoryService.status()
    }

    func refreshMemory() {
        memory = memoryService.status()
    }

    /// Mirrors the thermal state until the calling task is cancelled.
    func observeThermal() async {
        for await pressure in thermalService.pressureUpdates() {
            thermal = pressure
        }
    }
}
