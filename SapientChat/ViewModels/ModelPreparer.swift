import Foundation

/// Gets a model ready to use, shared by chat, the model manager and
/// compare: plans memory (releasing least recently used models so the new
/// one fits, keeping up to four together when they do), downloads it if its files
/// aren't complete, then loads it. Reports each phase as it starts.
struct ModelPreparer {
    let services: AppServices
    let device: DeviceStatus
    /// Show downloads in the Dynamic Island (API requests show their own).
    var showsDownloadIsland = true

    /// Ready `alias` and return the hardware label. Throws
    /// `ChatViewModelError.wontFit` before touching anything if it can't fit.
    func prepare(_ alias: String, onPhase: @escaping (ModelPhase) -> Void) async throws -> String {
        let catalog = services.catalog.chatModels()
        let model = catalog.first { $0.alias == alias }
        let loaded = await services.chat.loadedModels()

        if let model {
            device.refreshMemory()
            // CPU + GPU holds a full-precision model twice: plan for that, so
            // it's refused with a reason instead of iOS ending the app.
            let plan = MemoryPlanner.plan(
                loading: model.forPlanning(backend: EngineBackendPreference.backend(for: model)),
                loaded: loaded.map { name in (name, catalog.first { $0.alias == name }) },
                availableBytes: device.memory.availableBytes
            )
            switch plan {
            case .alreadyLoaded:
                break
            case .wontFit(let message):
                throw ChatViewModelError.wontFit(message)
            case .load(let releasing):
                for name in releasing {
                    await services.chat.unload(model: name)
                }
                if !services.storage.download(forRepo: model.repoId).isDownloaded {
                    try await download(alias, onPhase: onPhase)
                }
            }
        }
        if !loaded.contains(alias) {
            onPhase(.loading)
        }
        let backend = try await services.chat.load(model: alias)
        device.refreshMemory()
        return backend
    }

    /// Downloads `alias` through the app's shared `DownloadCoordinator`, so
    /// a download someone else started is joined, and cancelling this call
    /// stops only this caller, not the download.
    func download(_ alias: String, onPhase: @escaping (ModelPhase) -> Void) async throws {
        onPhase(.downloading(.starting))
        try await services.downloadCoordinator.download(alias, showsIsland: showsDownloadIsland) { progress in
            onPhase(.downloading(progress))
        }
    }
}
