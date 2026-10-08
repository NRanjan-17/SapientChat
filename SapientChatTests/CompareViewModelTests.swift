// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Testing
@testable import SapientChat

@MainActor
struct CompareViewModelTests {
    @Test func runsTheModelsOneAfterTheOther() async throws {
        let log = EventLog()
        let chat = ControlledChatService(autoReply: ["An", " answer"], log: log)
        let benchmark = InstantBenchmarkService(log: log, decodeRate: { $0 == TestModels.small.alias ? 20 : 30 })
        let services = makeServices(chat: chat, benchmark: benchmark, memory: FixedMemory())
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let compare = CompareViewModel(services: services, device: device, initialModel: TestModels.small.alias)
        #expect(compare.modelB == TestModels.big.alias, "B defaults to a different model")

        compare.run()

        #expect(await eventually { compare.phase == .finished })
        // A is loaded, answers and is benchmarked before B is touched.
        #expect(await log.events == [
            "load \(TestModels.small.alias)", "reply \(TestModels.small.alias)", "benchmark \(TestModels.small.alias)",
            "load \(TestModels.big.alias)", "reply \(TestModels.big.alias)", "benchmark \(TestModels.big.alias)",
        ])
        #expect(compare.results.map(\.answer) == ["An answer", "An answer"])
        let difference = try #require(compare.decodeDifferencePercent)
        #expect(abs(difference - 50) < 1e-9, "30 vs 20 tok/s is 50% faster")
        #expect(compare.results[1].memoryInUseBytes == 1_000_000_000)
    }

    @Test func stopsWithAClearMessageWhenAModelCannotFit() async {
        let log = EventLog()
        let chat = ControlledChatService(autoReply: ["ok"], log: log)
        let services = makeServices(chat: chat, memory: tightMemory)
        let device = DeviceStatus(memoryService: tightMemory, thermalService: SilentThermalService())
        let compare = CompareViewModel(services: services, device: device, initialModel: TestModels.small.alias)

        compare.run()

        #expect(await eventually {
            if case .failed(let message) = compare.phase { message.contains("smollm2-1.7b") } else { false }
        })
        #expect(await !log.events.contains("load \(TestModels.big.alias)"))
    }

    @Test func needsTwoDifferentModels() {
        let services = makeServices(chat: ControlledChatService())
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let compare = CompareViewModel(services: services, device: device, initialModel: TestModels.small.alias)
        compare.modelB = compare.modelA
        #expect(!compare.canRun)
    }
}
