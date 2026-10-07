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
    var contextWindows = ContextWindowStore.standard
    /// The Dynamic Island; nothing in tests and previews.
    var liveActivities: any LiveActivityService = NoLiveActivities()

    static func live() -> AppServices {
        let engine = SapientChatService(contextWindows: .standard)
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
