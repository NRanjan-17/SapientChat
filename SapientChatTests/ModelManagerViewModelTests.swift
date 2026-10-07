import Foundation
import Testing
@testable import SapientChat

@MainActor
struct ModelManagerViewModelTests {
    let service = ControlledChatService()

    private func makeManager(
        storage: FakeStorage = FakeStorage(),
        hangingDownload: Bool = false,
        memory: FixedMemory = FixedMemory(),
        onNewChat: @escaping (String) -> Void = { _ in }
    ) -> ModelManagerViewModel {
        let downloader = FakeDownloader(storage: storage, hangs: hangingDownload)
        let services = makeServices(chat: service, memory: memory, storage: storage, downloads: downloader)
        let device = DeviceStatus(memoryService: memory, thermalService: SilentThermalService())
        return ModelManagerViewModel(services: services, device: device, onNewChat: onNewChat)
    }

    private func row(_ model: PhoneModel, in manager: ModelManagerViewModel) -> ModelManagerViewModel.Row? {
        manager.rows.first { $0.model == model }
    }

    @Test func downloadShowsProgressThenDownloadedWithoutLoading() async throws {
        let storage = FakeStorage()
        let manager = makeManager(storage: storage)
        await manager.refresh()
        manager.download(try #require(row(TestModels.small, in: manager)))

        #expect(await eventually {
            if case .downloading(let progress) = row(TestModels.small, in: manager)?.activity { progress.fraction ?? 0 > 0 } else { false }
        })
        #expect(await eventually { row(TestModels.small, in: manager)?.download.isDownloaded == true })
        #expect(row(TestModels.small, in: manager)?.activity == nil)
        #expect(await service.loadedModels().isEmpty, "download alone does not load")
    }

    @Test func cancellingADownloadStopsIt() async throws {
        let manager = makeManager(hangingDownload: true)
        await manager.refresh()
        let small = try #require(row(TestModels.small, in: manager))
        manager.download(small)
        #expect(await eventually { row(TestModels.small, in: manager)?.activity != nil })

        manager.cancel(small)

        #expect(await eventually { row(TestModels.small, in: manager)?.activity == nil })
        #expect(row(TestModels.small, in: manager)?.download.isDownloaded == false)
        #expect(manager.errorMessage == nil, "a cancel is not an error")
    }

    @Test func loadingTwoModelsKeepsBothInMemory() async throws {
        let manager = makeManager(storage: downloadedStorage(), memory: FixedMemory(memory: MemoryStatus(footprintBytes: 0, availableBytes: 10_000_000_000)))
        await manager.refresh()
        manager.load(try #require(row(TestModels.small, in: manager)))
        #expect(await eventually { manager.loaded == [TestModels.small.alias] })
        manager.load(try #require(row(TestModels.big, in: manager)))

        #expect(await eventually { manager.loaded == [TestModels.big.alias, TestModels.small.alias] })
        #expect(manager.loadedRows.count == 2)
    }

    @Test func newChatLoadsTheModelFirst() async throws {
        var opened: String?
        let manager = makeManager(storage: downloadedStorage(), onNewChat: { opened = $0 })
        await manager.refresh()
        manager.startChat(try #require(row(TestModels.small, in: manager)))

        #expect(await eventually { opened == TestModels.small.alias })
        #expect(await service.loadedModels() == [TestModels.small.alias], "the chat opens with its model ready")
    }

    @Test func aModelThatCannotFitReportsWhy() async throws {
        let manager = makeManager(storage: downloadedStorage(), memory: tightMemory)
        await manager.refresh()
        let big = try #require(row(TestModels.big, in: manager))
        #expect(!big.fits)
        manager.load(big)
        #expect(await eventually { manager.errorMessage?.contains("smollm2-1.7b") == true })
        #expect(await service.loadedModels().isEmpty)
    }

    @Test func unloadFreesTheSlot() async throws {
        let manager = makeManager(storage: downloadedStorage())
        _ = try await service.load(model: TestModels.small.alias)
        await manager.refresh()
        await manager.unload(try #require(row(TestModels.small, in: manager)))
        #expect(manager.loaded.isEmpty)
    }
}

struct ReleaseNoticeTests {
    @Test func saysWhetherSlotsOrMemoryCausedTheRelease() {
        let slots = ModelManagerViewModel.releaseNotice(loading: "c", released: ["a"], availableBytes: 1_000_000_000, slotsFull: true)
        #expect(slots.contains("all model slots were in use"))
        let memory = ModelManagerViewModel.releaseNotice(loading: "c", released: ["a", "b"], availableBytes: 1_000_000_000, slotsFull: false)
        #expect(memory.contains("released a and b to make room in memory"))
        #expect(memory.contains("iOS allowed only"))
    }
}
