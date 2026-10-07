import Foundation
import SwiftData
import Testing
@testable import SapientChat

@MainActor
struct DownloadCoordinatorTests {
    private func makeCoordinator(
        storage: FakeStorage = FakeStorage(), steps: Int = 4, hangs: Bool = false, log: EventLog? = nil
    ) -> DownloadCoordinator {
        DownloadCoordinator(
            downloads: FakeDownloader(storage: storage, steps: steps, hangs: hangs, log: log),
            catalog: FixedCatalog()
        )
    }

    @Test func twoCallersShareOneDownload() async throws {
        let log = EventLog()
        let storage = FakeStorage()
        let coordinator = makeCoordinator(storage: storage, log: log)
        async let first: Void = coordinator.download(TestModels.small.alias) { _ in }
        async let second: Void = coordinator.download(TestModels.small.alias) { _ in }
        _ = try await (first, second)
        #expect(await log.events.filter { $0.hasPrefix("download") }.count == 1)
        #expect(storage.download(forRepo: TestModels.small.repoId).isDownloaded)
    }

    @Test func aCallerThatLeavesDoesNotStopTheDownload() async throws {
        let storage = FakeStorage()
        let coordinator = makeCoordinator(storage: storage, steps: 20)
        let caller = Task { try await coordinator.download(TestModels.small.alias) { _ in } }
        #expect(await eventually { coordinator.isDownloading(TestModels.small.alias) })
        caller.cancel()
        await #expect(throws: CancellationError.self) { try await caller.value }
        #expect(coordinator.isDownloading(TestModels.small.alias), "still downloading")
        #expect(await eventually { storage.download(forRepo: TestModels.small.repoId).isDownloaded })
    }

    @Test func cancelStopsItForEveryone() async throws {
        let coordinator = makeCoordinator(hangs: true)
        let first = Task { try await coordinator.download(TestModels.small.alias) { _ in } }
        let second = Task { try await coordinator.download(TestModels.small.alias) { _ in } }
        #expect(await eventually { coordinator.isDownloading(TestModels.small.alias) })
        coordinator.cancel(TestModels.small.alias)
        await #expect(throws: (any Error).self) { try await first.value }
        await #expect(throws: (any Error).self) { try await second.value }
        #expect(!coordinator.isDownloading(TestModels.small.alias))
    }

    @Test func reportsEveryDownloadThenItsEnd() async throws {
        let coordinator = makeCoordinator()
        var changes: [Bool] = []
        coordinator.onChange = { _, progress in changes.append(progress != nil) }
        try await coordinator.download(TestModels.small.alias) { _ in }
        #expect(changes.first == true)
        #expect(changes.last == false)
    }
}

@MainActor
struct LeavingAChatKeepsItsDownloadTests {
    @Test func theModelsTabShowsAChatsDownloadAfterTheChatIsLeft() async throws {
        let storage = FakeStorage()
        let chat = ControlledChatService(autoReply: ["ok"])
        let services = makeServices(chat: chat, storage: storage, downloads: FakeDownloader(storage: storage, steps: 30))
        let container = try makeContainer()
        let list = ChatListViewModel(services: services, store: SwiftDataConversationStore(context: container.mainContext))
        await list.models.refresh() // the Models tab loads its rows when shown
        list.newChat(model: TestModels.small.alias)
        let active = try #require(list.activeChat)
        active.draft = "Hi"
        active.send()
        #expect(await eventually { services.downloadCoordinator.isDownloading(TestModels.small.alias) })

        list.selectedID = nil // back to the list: the chat stops
        #expect(await eventually { list.models.rows.first { $0.model == TestModels.small }?.activity != nil },
                "the Models tab shows the download")
        #expect(await eventually { storage.download(forRepo: TestModels.small.repoId).isDownloaded },
                "and it finishes")
    }

    @Test func unloadAllReleasesEveryModel() async throws {
        let chat = ControlledChatService()
        let container = try makeContainer()
        let list = ChatListViewModel(
            services: makeServices(chat: chat, memory: FixedMemory(memory: MemoryStatus(footprintBytes: 0, availableBytes: 10_000_000_000))),
            store: SwiftDataConversationStore(context: container.mainContext)
        )
        _ = try await chat.load(model: TestModels.small.alias)
        _ = try await chat.load(model: TestModels.big.alias)
        await list.models.refresh()
        #expect(list.models.loaded.count == 2)
        await list.models.unloadAll()
        #expect(list.models.loaded.isEmpty)
        #expect(await chat.loadedModels().isEmpty)
    }
}
