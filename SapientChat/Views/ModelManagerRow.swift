// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

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
        let contextWindow: (ModelManagerViewModel.Row) -> Void
    }

    let row: ModelManagerViewModel.Row
    let actions: Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ModelTile(model: row.model, isLoaded: row.isLoaded)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(row.model.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    ModelManagerButtons(row: row, actions: actions)
                }
                ModelSpecChips(model: row.model)
                status
                if ContextWindowStore.isAdjustable(row.model), row.activity == nil {
                    Button(action: { actions.contextWindow(row) }) {
                        IconText(contextText, systemImage: "text.alignleft")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityHint("Changes how much of a conversation the model can see")
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

    private var contextText: String {
        row.contextWindow.map { "Context: \($0.formatted()) tokens" } ?? "Context: Default"
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
                            IconText("Not downloaded", systemImage: "arrow.down.circle")
                                .foregroundStyle(.secondary)
                        } else {
                            IconText("Needs more memory than iOS allows now", systemImage: "exclamationmark.triangle.fill")
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
    var canDelete: Bool {
        download.bytes > 0 && activity == nil
    }
}
