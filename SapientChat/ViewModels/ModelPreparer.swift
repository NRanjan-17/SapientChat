import Foundation

/// Gets a model ready to use, shared by chat, the model manager and
/// compare: plans memory (releasing least recently used models so the new
/// one fits, keeping two together when they do), downloads it if its files
/// aren't complete, then loads it. Reports each phase as it starts.
struct ModelPreparer {
    let services: AppServices
    let device: DeviceStatus

    /// Ready `alias` and return the hardware label. Throws
    /// `ChatViewModelError.wontFit` before touching anything if it can't fit.
    func prepare(_ alias: String, onPhase: (ModelPhase) -> Void) async throws -> String {
        let catalog = services.catalog.chatModels()
        let model = catalog.first { $0.alias == alias }
        let loaded = await services.chat.loadedModels()

        if let model {
            device.refreshMemory()
            let plan = MemoryPlanner.plan(
                loading: model,
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

    /// Downloads `alias`, reporting progress in order on the main actor.
    func download(_ alias: String, onPhase: (ModelPhase) -> Void) async throws {
        onPhase(.downloading(.starting))
        let (updates, sink) = AsyncStream<DownloadProgress>.makeStream()
        let downloads = services.downloads
        let task = Task {
            defer { sink.finish() }
            try await downloads.download(model: alias) { sink.yield($0) }
        }
        try await withTaskCancellationHandler {
            for await progress in updates {
                onPhase(.downloading(progress))
            }
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}
