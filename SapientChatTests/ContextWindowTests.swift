import Foundation
import Testing
@testable import SapientChat

struct ContextWindowStoreTests {
    @Test func remembersAPickAndForgetsItOnDefault() {
        let store = makeContextWindowStore()
        #expect(store.tokens(for: "m") == nil)
        store.set(4096, for: "m")
        #expect(store.tokens(for: "m") == 4096)
        #expect(store.tokens(for: "other") == nil)
        store.set(nil, for: "m")
        #expect(store.tokens(for: "m") == nil)
    }

    @Test func ignoresWindowsOutsideTheChoices() {
        let store = makeContextWindowStore()
        store.set(16_384, for: "m")
        #expect(store.tokens(for: "m") == nil)
        #expect(ContextWindowStore.choices.max() == 8192)
    }

    @Test func onlyModelsFrom1Point4BCanPick() {
        #expect(!ContextWindowStore.isAdjustable(PhoneModel(alias: "a", repoId: "a", params: "1.24B", billions: 1.24)))
        #expect(ContextWindowStore.isAdjustable(PhoneModel(alias: "b", repoId: "b", params: "1.4B", billions: 1.4)))
        #expect(ContextWindowStore.isAdjustable(TestModels.big))
        #expect(!ContextWindowStore.isAdjustable(TestModels.small))
    }
}

@MainActor
struct ModelManagerContextWindowTests {
    @Test func changingTheWindowReloadsALoadedModel() async throws {
        let chat = ControlledChatService()
        let store = makeContextWindowStore()
        let memory = FixedMemory(memory: MemoryStatus(footprintBytes: 0, availableBytes: 10_000_000_000))
        let services = makeServices(chat: chat, memory: memory, contextWindows: store)
        let manager = ModelManagerViewModel(
            services: services, device: DeviceStatus(memoryService: memory, thermalService: SilentThermalService())
        )
        await manager.refresh()
        manager.load(try #require(manager.rows.first { $0.model == TestModels.big }))
        #expect(await eventually { manager.loaded == [TestModels.big.alias] })

        let row = try #require(manager.rows.first { $0.model == TestModels.big })
        manager.setContextWindow(2048, for: row)

        #expect(store.tokens(for: TestModels.big.alias) == 2048)
        #expect(await eventually { await chat.unloadCount == 1 && manager.loaded == [TestModels.big.alias] })
        #expect(await chat.loadedModels.filter { $0 == TestModels.big.alias }.count == 2, "loaded again")
    }

    @Test func changingTheWindowOfAModelNotInMemoryOnlySavesIt() async throws {
        let chat = ControlledChatService()
        let store = makeContextWindowStore()
        let manager = ModelManagerViewModel(
            services: makeServices(chat: chat, contextWindows: store),
            device: DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        )
        await manager.refresh()
        manager.setContextWindow(8192, for: try #require(manager.rows.first { $0.model == TestModels.big }))
        #expect(store.tokens(for: TestModels.big.alias) == 8192)
        #expect(await chat.unloadCount == 0)
        #expect(await chat.loadedModels.isEmpty)
    }
}
