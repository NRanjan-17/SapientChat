// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Testing
@testable import SapientChat

struct ComputePreferenceTests {
    @Test func automaticPrefersCPUAndGPUAndFallsBackToTheGPUUnderLoad() {
        let auto = ComputePreference.automatic
        let eightGB: UInt64 = 8 * 1024 * 1024 * 1024
        #expect(auto.backend(thermal: .nominal, lowPower: false, physicalMemory: eightGB) == "hybrid")
        #expect(auto.backend(thermal: .fair, lowPower: false, physicalMemory: eightGB) == "hybrid")
        #expect(auto.backend(thermal: .serious, lowPower: false) == "wgpu")
        #expect(auto.backend(thermal: .critical, lowPower: false) == "wgpu")
        #expect(auto.backend(thermal: .nominal, lowPower: true) == "wgpu")
    }

    @Test func automaticUsesTheGPUAloneWhereCPUAndGPUWouldNeedTwoCopies() {
        let auto = ComputePreference.automatic
        let eightGB: UInt64 = 8 * 1024 * 1024 * 1024
        let fourGB: UInt64 = 4 * 1024 * 1024 * 1024
        #expect(auto.backend(thermal: .nominal, lowPower: false, isMemoryMapped: true, physicalMemory: eightGB) == "hybrid")
        // A full-precision model would be held twice (the 4 GB iPad memory kill).
        #expect(auto.backend(thermal: .nominal, lowPower: false, isMemoryMapped: false, physicalMemory: eightGB) == "wgpu")
        #expect(auto.backend(thermal: .nominal, lowPower: false, isMemoryMapped: true, physicalMemory: fourGB) == "wgpu")
    }

    @Test func cpuAndGPUPlansForTwoCopiesOfAFullModel() {
        let full = PhoneModel(alias: "full", repoId: "full", params: "1.1B", billions: 1.1)
        let q4 = PhoneModel(alias: "q4", repoId: "q4", params: "1.5B Q4_K_M", billions: 1.5)
        #expect(!full.isMemoryMapped && q4.isMemoryMapped)
        #expect(full.forPlanning(backend: "hybrid").estimatedMemoryBytes > full.estimatedMemoryBytes * 3 / 2)
        #expect(full.forPlanning(backend: "wgpu").estimatedMemoryBytes == full.estimatedMemoryBytes)
        #expect(q4.forPlanning(backend: "hybrid").estimatedMemoryBytes == q4.estimatedMemoryBytes)
        let available: UInt64 = 2_500_000_000
        #expect(full.fitProblem(availableBytes: available) == nil, "fits once")
        #expect(full.forPlanning(backend: "hybrid").fitProblem(availableBytes: available) != nil, "not twice")
    }

    @Test func aManualChoiceIsKeptWhateverTheState() {
        for thermal in [ProcessInfo.ThermalState.nominal, .critical] {
            #expect(ComputePreference.hybrid.backend(thermal: thermal, lowPower: true) == "hybrid")
            #expect(ComputePreference.gpu.backend(thermal: thermal, lowPower: false) == "wgpu")
            #expect(ComputePreference.cpu.backend(thermal: thermal, lowPower: false) == "cpu")
        }
    }

    @Test func backgroundServingAlwaysUsesTheCPU() {
        let defaults = UserDefaults(suiteName: "compute-\(UUID().uuidString)")!
        defaults.set(ComputePreference.gpu.rawValue, forKey: EngineBackendPreference.computeKey)
        #expect(EngineBackendPreference.backend(defaults, thermal: .nominal, lowPower: false) == "wgpu")
        #expect(EngineBackendPreference.backend(defaults, override: .hybrid, thermal: .nominal, lowPower: false) == "hybrid")
        defaults.set(true, forKey: EngineBackendPreference.cpuOnlyKey)
        #expect(EngineBackendPreference.backend(defaults, override: .hybrid, thermal: .nominal, lowPower: false) == "cpu")
    }

    @Test func theSettingDefaultsToAutomatic() {
        let defaults = UserDefaults(suiteName: "compute-\(UUID().uuidString)")!
        #expect(EngineBackendPreference.compute(defaults) == .automatic)
    }

    @Test func theChatShowsWhereTheModelRuns() {
        #expect(ChatViewModel.hardware("hybrid: prompt on wgpu (Apple A17 Pro GPU (Metal)) · generation on cpu") == "CPU + GPU")
        #expect(ChatViewModel.hardware("wgpu (Apple A14 GPU (Metal))") == "GPU")
        #expect(ChatViewModel.hardware("cpu") == "CPU")
    }
}
