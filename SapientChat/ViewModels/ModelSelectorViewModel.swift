// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

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

    /// Models fully on this device, in catalog order.
    var downloadedRows: [Row] { filtered.filter(\.download.isDownloaded) }
    /// Everything else (including paused downloads), in catalog order.
    var notDownloadedRows: [Row] { filtered.filter { !$0.download.isDownloaded } }

    private var filtered: [Row] {
        guard !searchText.isEmpty else { return rows }
        return rows.filter {
            $0.model.alias.localizedStandardContains(searchText) || $0.model.params.localizedStandardContains(searchText)
        }
    }

    func refresh() async {
        let loadedAliases = await services.chat.loadedModels()
        device.refreshMemory()
        let catalog = services.catalog.chatModels()
        let loaded = loadedAliases.map { name in (alias: name, model: catalog.first { $0.alias == name }) }
        rows = catalog.map { model in
            let plan = MemoryPlanner.plan(loading: model, loaded: loaded, availableBytes: device.memory.availableBytes)
            return Row(
                model: model,
                download: services.storage.download(forRepo: model.repoId),
                fits: plan.fits,
                isSelected: model.alias == selectedAlias,
                isLoaded: loadedAliases.contains(model.alias)
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
            await services.chat.unload(model: row.model.alias)
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
        await services.chat.unloadAll()
        do {
            try services.storage.deleteAllDownloads()
        } catch {
            errorMessage = "Couldn't delete downloads: \(error.localizedDescription)"
        }
        await refresh()
    }
}
