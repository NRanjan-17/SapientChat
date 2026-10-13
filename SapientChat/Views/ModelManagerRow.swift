// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// One model in the manager, App Store style: the maker's logo, name, spec
/// chips and a status line, with one primary action on the right and the
/// rest (including Delete) in a ⋯ menu.
struct ModelManagerRow: View {
    struct Actions {
        let download: (ModelManagerViewModel.Row) -> Void
        let cancel: (ModelManagerViewModel.Row) -> Void
        let load: (ModelManagerViewModel.Row) -> Void
        let unload: (ModelManagerViewModel.Row) -> Void
        let startChat: (ModelManagerViewModel.Row) -> Void
        let delete: (ModelManagerViewModel.Row) -> Void
        /// Opens Model Settings (temperature, context window).
        let settings: (ModelManagerViewModel.Row) -> Void
    }

    let row: ModelManagerViewModel.Row
    let actions: Actions
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModelTile(model: row.model, isLoaded: row.isLoaded)
            VStack(alignment: .leading, spacing: 6) {
                if dynamicTypeSize.isAccessibilitySize {
                    // At large text sizes the name gets the full width and
                    // the buttons a row of their own.
                    Text(row.model.displayName)
                        .font(.headline)
                    ModelManagerButtons(row: row, actions: actions)
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        Text(row.model.displayName)
                            .font(.headline)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        ModelManagerButtons(row: row, actions: actions)
                    }
                }
                ModelSpecChips(model: row.model)
                status
                // Settings matter once the model is here; before that
                // they're in the ⋯ menu.
                if row.activity == nil && row.download.isDownloaded {
                    Button(action: { actions.settings(row) }) {
                        IconText(settingsText, systemImage: "slider.horizontal.3")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Changes the model's temperature and context window")
                }
            }
            // Separators start under the text, the same for every row.
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        }
        .padding(.vertical, 6)
        .contextMenu { ModelManagerMenuItems(row: row, actions: actions) }
        .swipeActions {
            if row.canDelete {
                Button("Delete", systemImage: "trash", role: .destructive) { actions.delete(row) }
            }
        }
        .animation(.smooth, value: row.activity)
        .animation(.smooth, value: row.isLoaded)
    }

    /// "Temperature 0.7 · Context 3,072", the context part only for models
    /// that can pick one.
    private var settingsText: String {
        var parts = ["Temperature \(TemperatureStore.label(row.temperature))"]
        if ContextWindowStore.isAdjustable(row.model) {
            parts.append(row.contextWindow.map { "Context \($0.formatted())" } ?? "Context Default")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var status: some View {
        switch row.activity {
        case .downloading(let progress):
            DownloadProgressView(progress: progress, tint: row.model.tint)
        case .loading:
            IconText("Loading into memory…", systemImage: "memorychip")
                .font(.caption)
                .foregroundStyle(.secondary)
        case nil:
            Group {
                if row.isLoaded {
                    IconText("In memory · \(Format.bytes(row.download.bytes)) on device", systemImage: "memorychip.fill")
                        .foregroundStyle(.tint)
                } else {
                    switch row.download {
                    case .downloaded(let bytes):
                        IconText("Downloaded · \(Format.bytes(bytes))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                    case .partial(let bytes):
                        IconText("Paused at \(Format.bytes(bytes))", systemImage: "arrow.down.circle.dotted")
                            .foregroundStyle(.secondary)
                    case .notDownloaded:
                        if row.fits {
                            IconText("\(row.model.downloadSizeText) download", systemImage: "arrow.down.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            IconText("Too large for the memory free right now", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .font(.caption)
        }
    }
}

extension ModelManagerViewModel.Row {
    var isDownloading: Bool {
        if case .downloading = activity { true } else { false }
    }

    var canDelete: Bool {
        download.bytes > 0 && activity == nil
    }
}
