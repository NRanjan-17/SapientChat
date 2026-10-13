// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

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
        guard let model = catalog.first(where: { $0.alias == alias }) else {
            return try await services.chat.load(model: alias)
        }
        if await services.chat.loadedModels().contains(alias) {
            return try await services.chat.load(model: alias)
        }
        // Refuse early, with a reason, before a long download.
        _ = try await plan(model)
        if !services.storage.download(forRepo: model.repoId).isDownloaded {
            try await download(alias, onPhase: onPhase)
        }
        // Release idle models only now (they stayed usable during the
        // download), then plan again with memory as measured after
        // releasing: freed memory can come back late, and an estimate isn't
        // trusted to have made room.
        while case .load(let releasing) = try await plan(model), !releasing.isEmpty {
            for name in releasing {
                await services.chat.unload(model: name)
            }
            await waitForMemoryToSettle()
        }
        if await services.chat.loadedModels().contains(alias) {
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
        if let old = before.residentBytes, let new = device.memory.residentBytes, new > old {
            grew = new - old
        }
        services.memoryLedger.finishLoad(alias, grewBy: grew)
        return backend
    }

    /// The memory plan for `model` right now; throws when it can't load.
    private func plan(_ model: PhoneModel) async throws -> LoadPlan {
        device.refreshMemory()
        let catalog = services.catalog.chatModels()
        let plan = MemoryPlanner.plan(
            loading: model,
            loaded: await services.chat.loadedModels().map { name in (name, catalog.first { $0.alias == name }) },
            availableBytes: device.memory.availableBytes,
            busy: await services.chat.busyModels(),
            size: services.plannedSize
        )
        switch plan {
        case .wontFit(let message): throw ChatViewModelError.wontFit(message)
        case .busy(let message): throw ChatViewModelError.busy(message)
        case .alreadyLoaded, .load: return plan
        }
    }

    /// Released models' memory (GPU buffers especially) can return a moment
    /// after the release: waits until the reading stops changing, up to 1 s.
    private func waitForMemoryToSettle() async {
        device.refreshMemory()
        var last = device.memory.availableBytes
        for _ in 0..<10 {
            try? await Task.sleep(for: .milliseconds(100))
            device.refreshMemory()
            let now = device.memory.availableBytes
            if now == last { return }
            last = now
        }
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
