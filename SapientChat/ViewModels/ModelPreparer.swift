// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Gets a model ready to use, shared by chat, the model manager, compare
/// and the API: plans memory (releasing idle models, least recently used
/// first, so the new one fits; never one that's answering), downloads it if
/// its files aren't complete, then loads it, measuring what it really took.
/// Reports each phase as it starts.
struct ModelPreparer {
    let services: AppServices
    let device: DeviceStatus
    /// Show downloads in the Dynamic Island (API requests show their own).
    var showsDownloadIsland = true

    /// Ready `alias` and return the hardware label. Throws
    /// `ChatViewModelError.wontFit` (or `.busy`, when only a model that's
    /// answering is in the way) before touching anything if it can't fit.
    func prepare(_ alias: String, onPhase: @escaping (ModelPhase) -> Void) async throws -> String {
        let catalog = services.catalog.chatModels()
        let model = catalog.first { $0.alias == alias }
        let loaded = await services.chat.loadedModels()

        if let model {
            device.refreshMemory()
            // Planned at its real size when that's known, so it's refused
            // with a reason instead of iOS ending the app.
            let plan = MemoryPlanner.plan(
                loading: model,
                loaded: loaded.map { name in (name, catalog.first { $0.alias == name }) },
                availableBytes: device.memory.availableBytes,
                busy: await services.chat.busyModels(),
                size: services.plannedSize
            )
            switch plan {
            case .alreadyLoaded:
                break
            case .wontFit(let message):
                throw ChatViewModelError.wontFit(message)
            case .busy(let message):
                throw ChatViewModelError.busy(message)
            case .load(let releasing):
                for name in releasing {
                    await services.chat.unload(model: name)
                }
                if !services.storage.download(forRepo: model.repoId).isDownloaded {
                    try await download(alias, onPhase: onPhase)
                }
            }
        }
        guard !loaded.contains(alias) else {
            return try await services.chat.load(model: alias)
        }
        onPhase(.loading)
        device.refreshMemory()
        let before = device.memory
        // Written down first: if iOS ends the app mid-load, the next launch
        // knows which model did it.
        services.memoryLedger.beginLoad(alias, availableBytes: before.availableBytes)
        let backend: String
        do {
            backend = try await services.chat.load(model: alias)
        } catch {
            services.memoryLedger.abandonLoad()
            throw error
        }
        device.refreshMemory()
        var grew: UInt64?
        if let old = before.footprintBytes, let new = device.memory.footprintBytes, new > old {
            grew = new - old
        }
        services.memoryLedger.finishLoad(alias, grewBy: grew)
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
