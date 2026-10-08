// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Pick a model for the chat and manage downloads: downloaded models first,
/// then the rest. Models too large for this device right now can't be picked.
struct ModelSelectorView: View {
    @Bindable var viewModel: ModelSelectorViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: ModelSelectorViewModel.Row?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                ModelSection(
                    title: "Downloaded",
                    rows: viewModel.downloadedRows,
                    canSelect: viewModel.canSelect,
                    onSelect: select,
                    onDelete: confirmDelete
                )
                ModelSection(
                    title: "Not downloaded",
                    footer: "Models download the first time you use them.",
                    rows: viewModel.notDownloadedRows,
                    canSelect: viewModel.canSelect,
                    onSelect: select,
                    onDelete: confirmDelete
                )
                Section {
                    LabeledContent("Downloaded", value: Format.bytes(viewModel.totalDownloadBytes))
                    Button("Delete All Downloads", systemImage: "trash", role: .destructive) {
                        isConfirmingDeleteAll = true
                    }
                    .disabled(viewModel.totalDownloadBytes == 0)
                } footer: {
                    Text("Deleted models download again the next time you use them.")
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Search models")
            .readableContentWidth(720)
            .navigationTitle(viewModel.canSelect ? "Choose Model" : "Downloaded Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
            .task { await viewModel.refresh() }
            .confirmationDialog(deleteTitle, isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: deletePending)
            }
            .confirmationDialog(
                "Delete all downloads (\(Format.bytes(viewModel.totalDownloadBytes)))?",
                isPresented: $isConfirmingDeleteAll,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive, action: deleteAll)
            }
            .alert("Couldn't Delete", isPresented: hasError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var hasError: Binding<Bool> {
        $viewModel.errorMessage.isPresent
    }

    private var deleteTitle: String {
        guard let row = pendingDelete, case .downloaded(let bytes) = row.download else { return "Delete download?" }
        return "Delete \(row.model.displayName) (\(Format.bytes(bytes)))?"
    }

    private func select(_ row: ModelSelectorViewModel.Row) {
        viewModel.select(row)
        dismiss()
    }

    private func confirmDelete(_ row: ModelSelectorViewModel.Row) {
        pendingDelete = row
        isConfirmingDelete = true
    }

    private func deletePending() {
        guard let row = pendingDelete else { return }
        Task { await viewModel.deleteDownload(row) }
    }

    private func deleteAll() {
        Task { await viewModel.deleteAllDownloads() }
    }

    private func close() {
        dismiss()
    }
}

extension Binding where Value == String? {
    /// True while the optional holds a value; setting false clears it.
    var isPresent: Binding<Bool> {
        Binding<Bool> { wrappedValue != nil } set: { if !$0 { wrappedValue = nil } }
    }
}

#Preview {
    ModelSelectorView(viewModel: .preview)
}
