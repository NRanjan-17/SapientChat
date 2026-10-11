// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import SwiftData
import Testing
@testable import SapientChat

struct TemperatureStoreTests {
    @Test func savesPerModelAndZeroMeansPrecise() {
        let store = makeTemperatureStore()
        #expect(store.temperature(for: "a") == nil, "greedy by default")
        store.set(0.7, for: "a")
        #expect(store.temperature(for: "a") == 0.7)
        #expect(store.temperature(for: "b") == nil, "per model")
        store.set(0, for: "a")
        #expect(store.temperature(for: "a") == nil, "0 is greedy")
        store.set(0.7, for: "a")
        store.set(nil, for: "a")
        #expect(store.temperature(for: "a") == nil)
    }

    @Test func clampsAndRoundsToTheSlider() {
        #expect(TemperatureStore.normalized(0.74) == 0.7)
        #expect(TemperatureStore.normalized(9) == 1.5)
        #expect(TemperatureStore.normalized(-1) == nil)
        #expect(TemperatureStore.normalized(0.04) == nil)
        #expect(TemperatureStore.label(nil) == "Precise")
        #expect(TemperatureStore.label(1.0) == "1.0")
    }
}

@MainActor
struct TemperatureReloadTests {
    @Test func changingTemperatureInModelsReloadsALoadedModelOnce() async throws {
        let chat = ControlledChatService()
        let temperatures = makeTemperatureStore()
        let memory = FixedMemory(memory: MemoryStatus(footprintBytes: 0, availableBytes: 10_000_000_000))
        let manager = ModelManagerViewModel(
            services: makeServices(chat: chat, memory: memory, temperatures: temperatures),
            device: DeviceStatus(memoryService: memory, thermalService: SilentThermalService())
        )
        await manager.refresh()
        manager.load(try #require(manager.rows.first { $0.model == TestModels.small }))
        #expect(await eventually { manager.loaded == [TestModels.small.alias] })

        let row = try #require(manager.rows.first { $0.model == TestModels.small })
        manager.setSettings(temperature: 0.7, contextWindow: nil, for: row)
        #expect(temperatures.temperature(for: TestModels.small.alias) == 0.7)
        #expect(await eventually { await chat.unloadCount == 1 && manager.loaded == [TestModels.small.alias] })
        #expect(await eventually { manager.rows.first { $0.model == TestModels.small }?.temperature == 0.7 })

        // Saving the same settings again doesn't reload.
        manager.setSettings(temperature: 0.7, contextWindow: nil, for: try #require(manager.rows.first { $0.model == TestModels.small }))
        try await Task.sleep(for: .milliseconds(100))
        #expect(await chat.unloadCount == 1)
    }

    @Test func aChatsTemperatureIsItsModelsAndReloadsIt() async throws {
        let container = try makeContainer()
        let store = SwiftDataConversationStore(context: container.mainContext)
        let chat = ControlledChatService()
        let temperatures = makeTemperatureStore()
        let services = makeServices(chat: chat, temperatures: temperatures)
        let conversation = store.createConversation(model: TestModels.small.alias)
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let viewModel = ChatViewModel(conversation: conversation, services: services, store: store, device: device)

        viewModel.draft = "Hi"
        viewModel.send()
        #expect(await eventually { await chat.replyCount == 1 })
        await chat.finishReply(0)
        #expect(await eventually { viewModel.status == .idle })
        await viewModel.refreshModelDetails()

        viewModel.temperature = 1.0
        #expect(temperatures.temperature(for: TestModels.small.alias) == 1.0)
        #expect(viewModel.temperature == 1.0)
        #expect(await eventually { await chat.unloadCount == 1 })
        #expect(await eventually { await chat.loadedModels.filter { $0 == TestModels.small.alias }.count == 2 }, "loaded again with it")
    }
}
