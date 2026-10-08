// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Sapient

/// `ThermalService` that also feeds every change into the engine, which
/// sheds decode threads under pressure and restores them as the device cools.
///
/// Two iOS traps handled here:
/// - `thermalState` must be read once BEFORE subscribing, or change
///   notifications never arrive.
/// - `isLowPowerModeEnabled` must not be read synchronously inside the
///   power-state notification callback (iOS 15 deadlock, FB9741207). The
///   async notification sequence reads it after the callback has returned.
nonisolated struct SapientThermalService: ThermalService {
    func pressureUpdates() -> AsyncStream<ThermalPressure> {
        let (stream, continuation) = AsyncStream<ThermalPressure>.makeStream()
        @Sendable func publish() {
            let pressure = Self.currentPressure()
            setThermalLevel(level: pressure.engineLevel)
            continuation.yield(pressure)
        }
        let task = Task {
            publish() // read before subscribing
            await withTaskGroup(of: Void.self) { group in
                for name in [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange] {
                    group.addTask {
                        for await _ in NotificationCenter.default.notifications(named: name) {
                            publish()
                        }
                    }
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }

    private static func currentPressure() -> ThermalPressure {
        let info = ProcessInfo.processInfo
        let pressure: ThermalPressure = switch info.thermalState {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        @unknown default: .serious
        }
        // Low Power Mode already down-clocks the device: never run full speed.
        return info.isLowPowerModeEnabled && pressure == .nominal ? .fair : pressure
    }
}

nonisolated private extension ThermalPressure {
    var engineLevel: ThermalLevel {
        switch self {
        case .nominal: .nominal
        case .fair: .fair
        case .serious: .serious
        case .critical: .critical
        }
    }
}
