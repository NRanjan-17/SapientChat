// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Every service the ViewModels use, injected as one bundle so tests and
/// previews can swap in fakes. `live()` wires ONE engine for chat,
/// benchmark and compare, so only one model is ever in memory.
struct AppServices {
    let chat: any ChatService
    let benchmark: any BenchmarkService
    let catalog: any ModelCatalogService
    let thermal: any ThermalService
    let memory: any MemoryService
    let storage: any ModelStorageService
    let downloads: any ModelDownloadService
    /// Per-model context windows the user picked; the engine reads them at load.
    var contextWindows: ContextWindowStore
    /// Per-model sampling temperatures; the engine reads them at load.
    var temperatures: TemperatureStore
    /// The Dynamic Island; nothing in tests and previews.
    var liveActivities: any LiveActivityService {
        didSet { downloadCoordinator.liveActivities = liveActivities }
    }
    /// What models really took in memory, and the load in flight.
    let memoryLedger: ModelMemoryLedger
    /// Every model download goes through here, one per model, shared by
    /// whoever asks; leaving a chat doesn't stop its download.
    let downloadCoordinator: DownloadCoordinator

    init(
        chat: any ChatService,
        benchmark: any BenchmarkService,
        catalog: any ModelCatalogService,
        thermal: any ThermalService,
        memory: any MemoryService,
        storage: any ModelStorageService,
        downloads: any ModelDownloadService,
        contextWindows: ContextWindowStore = .standard,
        temperatures: TemperatureStore = .standard,
        liveActivities: any LiveActivityService = NoLiveActivities(),
        memoryLedger: ModelMemoryLedger = .standard
    ) {
        self.memoryLedger = memoryLedger
        self.chat = chat
        self.benchmark = benchmark
        self.catalog = catalog
        self.thermal = thermal
        self.memory = memory
        self.storage = storage
        self.downloads = downloads
        self.contextWindows = contextWindows
        self.temperatures = temperatures
        self.liveActivities = liveActivities
        downloadCoordinator = DownloadCoordinator(downloads: downloads, catalog: catalog)
        downloadCoordinator.liveActivities = liveActivities
    }

    static func live() -> AppServices {
        let engine = SapientChatService(contextWindows: .standard, temperatures: .standard)
        return AppServices(
            chat: engine,
            benchmark: engine,
            catalog: SapientModelCatalog(),
            thermal: SapientThermalService(),
            memory: SapientMemoryService(),
            storage: HubModelStorage.appDefault,
            downloads: SapientModelDownloader()
        )
    }
}

extension AppServices {
    /// Memory `model` takes once loaded, for planning: the estimate (twice
    /// for a full-precision model on CPU + GPU), or what it really took when
    /// that was more.
    func plannedSize(_ model: PhoneModel) -> UInt64 {
        let estimate = model.forPlanning(backend: EngineBackendPreference.backend(for: model)).estimatedMemoryBytes
        return max(estimate, memoryLedger.requiredBytes(for: model.alias) ?? 0)
    }
}
