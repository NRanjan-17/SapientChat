import Foundation
import Testing
@testable import SapientChat

@MainActor
struct ModelSelectorViewModelTests {
    let service = ControlledChatService()

    private func makeSelector(
        memory: FixedMemory = tightMemory,
        storage: FakeStorage = FakeStorage(downloads: [TestModels.small.repoId: 105_000_000]),
        onSelect: ((String) -> Void)? = { _ in }
    ) -> ModelSelectorViewModel {
        let services = makeServices(chat: service, memory: memory, storage: storage)
        let device = DeviceStatus(memoryService: memory, thermalService: SilentThermalService())
        return ModelSelectorViewModel(selected: TestModels.small.alias, services: services, device: device, onSelect: onSelect)
    }

    @Test func groupsModelsByWhetherTheyFit() async {
        let selector = makeSelector()
        await selector.refresh()
        #expect(selector.fittingRows.map(\.model.alias) == [TestModels.small.alias])
        #expect(selector.tooLargeRows.map(\.model.alias) == [TestModels.big.alias])
        #expect(selector.fittingRows.first?.isSelected == true)
    }

    @Test func showsWhatIsDownloaded() async {
        let selector = makeSelector()
        await selector.refresh()
        #expect(selector.fittingRows.first?.download == .downloaded(bytes: 105_000_000))
        #expect(selector.tooLargeRows.first?.download == .notDownloaded)
        #expect(selector.totalDownloadBytes == 105_000_000)
    }

    @Test func searchFilters() async {
        let selector = makeSelector(memory: FixedMemory())
        await selector.refresh()
        selector.searchText = "1.7b"
        #expect(selector.fittingRows.map(\.model.alias) == [TestModels.big.alias])
    }

    @Test func selectingReportsTheModel() async {
        var picked: String?
        let selector = makeSelector(memory: FixedMemory(), onSelect: { picked = $0 })
        await selector.refresh()
        let big = try! #require(selector.fittingRows.first { $0.model == TestModels.big })
        selector.select(big)
        #expect(picked == TestModels.big.alias)
        #expect(selector.selectedAlias == TestModels.big.alias)
    }

    @Test func deletingTheLoadedModelUnloadsItFirst() async throws {
        let storage = FakeStorage(downloads: [TestModels.small.repoId: 105_000_000])
        _ = try await service.load(model: TestModels.small.alias)
        let selector = makeSelector(storage: storage)
        await selector.refresh()
        let row = try #require(selector.fittingRows.first)
        #expect(row.isLoaded)

        await selector.deleteDownload(row)

        #expect(await service.unloadCount == 1)
        #expect(await service.loadedModel() == nil)
        #expect(storage.download(forRepo: TestModels.small.repoId) == .notDownloaded)
        #expect(selector.totalDownloadBytes == 0)
    }

    @Test func deleteAllRemovesEverything() async {
        let storage = FakeStorage(downloads: [TestModels.small.repoId: 100, TestModels.big.repoId: 200])
        let selector = makeSelector(storage: storage)
        await selector.refresh()
        await selector.deleteAllDownloads()
        #expect(selector.totalDownloadBytes == 0)
        #expect(await service.unloadCount == 1)
    }
}
