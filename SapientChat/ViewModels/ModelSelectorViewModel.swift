import Foundation
import Observation

/// The model picker and download manager: which models fit this device,
/// which are downloaded, and deleting downloads.
@Observable
final class ModelSelectorViewModel: Identifiable {
    let id = UUID()
    struct Row: Identifiable, Equatable {
        let model: PhoneModel
        let download: ModelDownload
        let fits: Bool
        let isSelected: Bool
        let isLoaded: Bool

        var id: String { model.id }
    }

    var searchText = ""
    private(set) var rows: [Row] = []
    private(set) var totalDownloadBytes: UInt64 = 0
    var errorMessage: String?
    /// The chat's current model; nil when the screen only manages downloads.
    private(set) var selectedAlias: String?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let device: DeviceStatus
    @ObservationIgnored private let onSelect: ((String) -> Void)?

    init(selected: String?, services: AppServices, device: DeviceStatus, onSelect: ((String) -> Void)?) {
        selectedAlias = selected
        self.services = services
        self.device = device
        self.onSelect = onSelect
    }

    var canSelect: Bool { onSelect != nil }

    var fittingRows: [Row] { filtered.filter(\.fits) }
    var tooLargeRows: [Row] { filtered.filter { !$0.fits } }

    private var filtered: [Row] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.model.alias.localizedStandardContains(searchText) || $0.model.params.localizedStandardContains(searchText)
        }
    }

    func refresh() async {
        let loaded = await services.chat.loadedModel()
        device.refreshMemory()
        let reclaimable = loaded == nil ? 0 : device.memory.footprintBytes ?? 0
        rows = services.catalog.chatModels().map { model in
            Row(
                model: model,
                download: services.storage.download(forRepo: model.repoId),
                fits: model.fitProblem(availableBytes: device.memory.availableBytes, reclaimableBytes: reclaimable) == nil,
                isSelected: model.alias == selectedAlias,
                isLoaded: model.alias == loaded
            )
        }
        totalDownloadBytes = services.storage.totalDownloadBytes()
    }

    func select(_ row: Row) {
        guard let onSelect else { return }
        selectedAlias = row.model.alias
        onSelect(row.model.alias)
    }

    /// Deletes one model's files, unloading it first if it is in memory.
    func deleteDownload(_ row: Row) async {
        if row.isLoaded {
            await services.chat.unload()
        }
        do {
            try services.storage.deleteDownload(forRepo: row.model.repoId)
        } catch {
            errorMessage = "Couldn't delete \(row.model.displayName): \(error.localizedDescription)"
        }
        await refresh()
    }

    /// Deletes every download (tokenizers too), unloading the model first.
    func deleteAllDownloads() async {
        await services.chat.unload()
        do {
            try services.storage.deleteAllDownloads()
        } catch {
            errorMessage = "Couldn't delete downloads: \(error.localizedDescription)"
        }
        await refresh()
    }
}
