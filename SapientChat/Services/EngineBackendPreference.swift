// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Which backend the engine loads a model on: the user's Compute choice
/// (Settings), except while the API server runs in the background, where
/// it's the CPU (iOS doesn't allow GPU work from a background app).
nonisolated enum EngineBackendPreference {
    /// Set while serving in the background.
    static let cpuOnlyKey = "engine.cpuOnly"
    /// The Compute setting (`ComputePreference` raw value).
    static let computeKey = "engine.compute"

    static func cpuOnly(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: cpuOnlyKey)
    }

    static func compute(_ defaults: UserDefaults = .standard) -> ComputePreference {
        defaults.string(forKey: computeKey).flatMap(ComputePreference.init(rawValue:)) ?? .automatic
    }

    /// The backend for loading `model` next. `override` is a benchmark's own pick.
    static func backend(
        _ defaults: UserDefaults = .standard,
        for model: PhoneModel? = nil,
        override: ComputePreference? = nil,
        thermal: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState,
        lowPower: Bool = ProcessInfo.processInfo.isLowPowerModeEnabled,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> String {
        if cpuOnly(defaults) { return "cpu" }
        return (override ?? compute(defaults)).backend(
            thermal: thermal, lowPower: lowPower,
            isMemoryMapped: model?.isMemoryMapped ?? true, physicalMemory: physicalMemory
        )
    }
}
