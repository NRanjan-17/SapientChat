import Foundation
import Observation

/// The model manager: download models ahead of time, load them into
/// memory (up to two at once), unload, delete, and start a chat with a
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

        var id: String { model.id }
    }

    let id = UUID()
    let capacity = LoadedSlots<Void>.defaultCapacity
    private(set) var rows: [Row] = []
    /// Loaded models, most recently used first.
    private(set) var loaded: [String] = []
    private(set) var totalDownloadBytes: UInt64 = 0
    var errorMessage: String?
    let device: DeviceStatus

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let onNewChat: (String) -> Void
    private var activities: [String: Activity] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]

    init(services: AppServices, device: DeviceStatus, onNewChat: @escaping (String) -> Void) {
        self.services = services
        self.device = device
        self.onNewChat = onNewChat
    }

    var loadedRows: [Row] { rows.filter(\.isLoaded) }
    var otherRows: [Row] { rows.filter { !$0.isLoaded } }

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
                activity: activities[model.alias]
            )
        }
        totalDownloadBytes = services.storage.totalDownloadBytes()
    }

    /// Downloads without loading, so the model is ready offline later.
    func download(_ row: Row) {
        let alias = row.model.alias
        run(alias) { [self] in
            try await ModelPreparer(services: services, device: device).download(alias) { phase in
                if case .downloading(let progress) = phase { setActivity(.downloading(progress), for: alias) }
            }
        }
    }

    /// Downloads if needed and loads into memory (releasing the least
    /// recently used model if both slots are taken or memory is short).
    func load(_ row: Row) {
        let alias = row.model.alias
        run(alias) { [self] in
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

    func cancel(_ row: Row) {
        tasks[row.model.alias]?.cancel()
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
        try await ModelPreparer(services: services, device: device).prepare(alias) { phase in
            switch phase {
            case .downloading(let progress): setActivity(.downloading(progress), for: alias)
            case .loading: setActivity(.loading, for: alias)
            }
        }
    }

    /// Runs one task per model; the row shows its activity until it ends.
    private func run(_ alias: String, _ work: @escaping () async throws -> Void) {
        guard tasks[alias] == nil else { return }
        tasks[alias] = Task { [weak self] in
            do {
                try await work()
            } catch is CancellationError {
                // Cancelled by the user; partial downloads resume next time.
            } catch ChatViewModelError.wontFit(let message) {
                self?.errorMessage = message
            } catch {
                self?.errorMessage = String(describing: error)
            }
            self?.finish(alias)
        }
        Task { await refresh() }
    }

    private func setActivity(_ activity: Activity, for alias: String) {
        activities[alias] = activity
        rows = rows.map { row in
            guard row.model.alias == alias else { return row }
            return Row(model: row.model, download: row.download, isLoaded: row.isLoaded, fits: row.fits, activity: activity)
        }
    }

    private func finish(_ alias: String) {
        tasks[alias] = nil
        activities[alias] = nil
        Task { await refresh() }
    }
}
