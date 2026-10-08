// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// The model manager: download models ahead of time, load them into
/// memory (up to four at once), unload, delete, and start a chat with a
/// model that is already loaded.
@Observable
final class ModelManagerViewModel: Identifiable {
    enum Activity: Equatable {
        case downloading(DownloadProgress)
        case loading
    }

    struct Row: Identifiable, Equatable {
        let model: PhoneModel
        let download: ModelDownload
        let isLoaded: Bool
        let fits: Bool
        let activity: Activity?
        /// The picked context window; nil is the default. Only models of
        /// 1.4B and up can pick one (`ContextWindowStore.isAdjustable`).
        var contextWindow: Int?

        var id: String { model.id }
    }

    let id = UUID()
    let capacity = LoadedSlots<Void>.defaultCapacity
    private(set) var rows: [Row] = []
    /// Loaded models, most recently used first.
    private(set) var loaded: [String] = []
    private(set) var totalDownloadBytes: UInt64 = 0
    var errorMessage: String?
    /// Why a model was just released, e.g. to make room for another.
    var notice: String?
    let device: DeviceStatus
    /// Runs after "New Chat" has loaded the model.
    @ObservationIgnored var onNewChat: (String) -> Void

    @ObservationIgnored private let services: AppServices
    private var activities: [String: Activity] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    /// Dynamic Island per model, started at its first download or load step.
    @ObservationIgnored private var islands: [String: LiveActivityTracker] = [:]

    init(services: AppServices, device: DeviceStatus, onNewChat: @escaping (String) -> Void = { _ in }) {
        self.services = services
        self.device = device
        self.onNewChat = onNewChat
    }

    /// Order within each section, by the memory a model needs.
    var sort: ModelSort = .smallestFirst

    var loadedRows: [Row] { sorted(rows.filter(\.isLoaded)) }
    /// Models downloading or loading right now.
    var activeRows: [Row] { rows.filter { $0.activity != nil } }
    /// Downloaded but not in memory.
    var downloadedRows: [Row] { sorted(rows.filter { !$0.isLoaded && $0.download.isDownloaded }) }
    /// Not on this device yet, including paused downloads.
    var notDownloadedRows: [Row] { sorted(rows.filter { !$0.isLoaded && !$0.download.isDownloaded }) }

    private func sorted(_ rows: [Row]) -> [Row] {
        sort.sorted(rows, by: \.model)
    }

    func displayName(of alias: String) -> String {
        rows.first { $0.model.alias == alias }?.model.displayName ?? alias
    }

    func refresh() async {
        loaded = await services.chat.loadedModels()
        device.refreshMemory()
        let catalog = services.catalog.chatModels()
        let loadedModels = loaded.map { name in (alias: name, model: catalog.first { $0.alias == name }) }
        rows = catalog.map { model in
            Row(
                model: model,
                download: services.storage.download(forRepo: model.repoId),
                isLoaded: loaded.contains(model.alias),
                fits: MemoryPlanner.plan(loading: model, loaded: loadedModels, availableBytes: device.memory.availableBytes).fits,
                activity: activities[model.alias],
                contextWindow: services.contextWindows.tokens(for: model.alias)
            )
        }
        totalDownloadBytes = services.storage.totalDownloadBytes()
    }

    /// Downloads without loading, so the model is ready offline later.
    func download(_ row: Row) {
        let alias = row.model.alias
        run(alias, done: "Downloaded") { [self] in
            try await ModelPreparer(services: services, device: device).download(alias) { [self] phase in
                if case .downloading(let progress) = phase { setActivity(.downloading(progress), for: alias) }
            }
        }
    }

    /// Downloads if needed and loads into memory (releasing the least
    /// recently used model if every slot is taken or memory is short).
    func load(_ row: Row) {
        let alias = row.model.alias
        run(alias, done: "Loaded") { [self] in
            _ = try await prepare(alias)
        }
    }

    /// Makes sure the model is loaded, then opens a new chat with it.
    func startChat(_ row: Row) {
        let alias = row.model.alias
        run(alias) { [self] in
            _ = try await prepare(alias)
            onNewChat(alias)
        }
    }

    /// The context window picked for `row`'s model; nil is the engine default.
    func contextWindow(for row: Row) -> Int? {
        services.contextWindows.tokens(for: row.model.alias)
    }

    /// Saves a new context window, reloading the model if it's in memory.
    func setContextWindow(_ tokens: Int?, for row: Row) {
        guard tokens != contextWindow(for: row) else { return }
        let alias = row.model.alias
        services.contextWindows.set(tokens, for: alias)
        Task { await refresh() }
        guard row.isLoaded else { return }
        run(alias) { [self] in
            await services.chat.unload(model: alias)
            _ = try await prepare(alias)
        }
    }

    /// Stops the model's download for everyone (a chat waiting on it too),
    /// or its load.
    func cancel(_ row: Row) {
        services.downloadCoordinator.cancel(row.model.alias)
        tasks[row.model.alias]?.cancel()
    }

    /// Runs before Unload All: stops replies and benchmarks using the models.
    @ObservationIgnored var beforeUnloadAll: () -> Void = {}

    /// Releases every model from memory; they stay downloaded.
    func unloadAll() async {
        beforeUnloadAll()
        await services.chat.unloadAll()
        await refresh()
    }

    /// Any download in the app (a chat's, an API request's, this tab's),
    /// shown on its row; nil when it ends.
    func downloadChanged(_ progress: DownloadProgress?, for alias: String) {
        if let progress {
            setActivity(.downloading(progress), for: alias, showsIsland: false)
        } else if tasks[alias] == nil {
            activities[alias] = nil
            Task { await refresh() }
        }
    }

    func unload(_ row: Row) async {
        await services.chat.unload(model: row.model.alias)
        await refresh()
    }

    func deleteDownload(_ row: Row) async {
        if row.isLoaded {
            await services.chat.unload(model: row.model.alias)
        }
        do {
            try services.storage.deleteDownload(forRepo: row.model.repoId)
        } catch {
            errorMessage = "Couldn't delete \(row.model.displayName): \(error.localizedDescription)"
        }
        await refresh()
    }

    func deleteAllDownloads() async {
        await services.chat.unloadAll()
        do {
            try services.storage.deleteAllDownloads()
        } catch {
            errorMessage = "Couldn't delete downloads: \(error.localizedDescription)"
        }
        await refresh()
    }

    // MARK: Private

    private func prepare(_ alias: String) async throws -> String {
        let before = await services.chat.loadedModels()
        device.refreshMemory()
        let available = device.memory.availableBytes
        let backend = try await ModelPreparer(services: services, device: device).prepare(alias) { [self] phase in
            switch phase {
            case .downloading(let progress): setActivity(.downloading(progress), for: alias)
            case .loading: setActivity(.loading, for: alias)
            }
        }
        let after = await services.chat.loadedModels()
        let released = before.filter { !after.contains($0) }
        if !released.isEmpty {
            notice = Self.releaseNotice(loading: displayName(of: alias), released: released.map(displayName(of:)),
                                        availableBytes: available, slotsFull: before.count >= capacity)
        }
        return backend
    }

    private func island(for alias: String) -> LiveActivityTracker {
        if let island = islands[alias] { return island }
        let island = LiveActivityTracker(service: services.liveActivities, title: "Models")
        island.start(model: displayName(of: alias))
        islands[alias] = island
        return island
    }

    /// "To load X, released Y: iOS allowed only 1.2 GB more." Says whether
    /// it was the slot limit or memory, so neither looks like a hidden cap.
    static func releaseNotice(loading: String, released: [String], availableBytes: UInt64?, slotsFull: Bool) -> String {
        let names = released.formatted(.list(type: .and))
        if slotsFull {
            return "To load \(loading), released \(names): all model slots were in use."
        }
        let room = availableBytes.map { " iOS allowed only \(Format.bytes($0)) more." } ?? ""
        return "To load \(loading), released \(names) to make room in memory.\(room)"
    }

    /// Runs one task per model; the row shows its activity until it ends.
    private func run(_ alias: String, done: String = "Ready", _ work: @escaping () async throws -> Void) {
        guard tasks[alias] == nil else { return }
        tasks[alias] = Task { [weak self] in
            do {
                try await work()
                self?.islands[alias]?.finish(detail: done)
            } catch is CancellationError {
                // Cancelled by the user; partial downloads resume next time.
                self?.islands[alias]?.finish(detail: "Cancelled")
            } catch ChatViewModelError.wontFit(let message) {
                self?.errorMessage = message
                self?.islands[alias]?.fail(message)
            } catch {
                self?.errorMessage = String(describing: error)
                self?.islands[alias]?.fail(String(describing: error))
            }
            self?.islands[alias] = nil
            self?.finish(alias)
        }
        Task { await refresh() }
    }

    /// A download or load an API request is doing: shown on the model's row
    /// (its Dynamic Island is the request's own). nil when it's done.
    func apiPhase(_ phase: ModelPhase?, for alias: String) {
        guard tasks[alias] == nil else { return } // the Models tab's own work wins
        guard let phase else {
            activities[alias] = nil
            Task { await refresh() }
            return
        }
        switch phase {
        case .downloading(let progress): setActivity(.downloading(progress), for: alias, showsIsland: false)
        case .loading: setActivity(.loading, for: alias, showsIsland: false)
        }
    }

    private func setActivity(_ activity: Activity, for alias: String, showsIsland: Bool = true) {
        activities[alias] = activity
        // Downloads have the coordinator's Dynamic Island; loads get this tab's.
        if showsIsland, case .loading = activity {
            island(for: alias).phase(.loading)
        }
        rows = rows.map { row in
            guard row.model.alias == alias else { return row }
            return Row(
                model: row.model, download: row.download, isLoaded: row.isLoaded, fits: row.fits,
                activity: activity, contextWindow: row.contextWindow
            )
        }
    }

    private func finish(_ alias: String) {
        tasks[alias] = nil
        activities[alias] = nil
        Task { await refresh() }
    }
}
