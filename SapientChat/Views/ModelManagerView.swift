// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Download models ahead of time, load up to four into memory, unload,
/// delete, and start a chat with a model that's already loaded.
struct ModelManagerView: View {
    @Bindable var viewModel: ModelManagerViewModel
    @State private var pendingDelete: ModelManagerViewModel.Row?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDeleteAll = false
    @State private var isConfirmingUnloadAll = false
    @State private var settingsRow: ModelManagerViewModel.Row?

    var body: some View {
        NavigationStack {
            List {
                // Memory only matters once something is loaded; with
                // nothing in it the models come first.
                if !viewModel.loaded.isEmpty {
                    MemorySummarySection(
                        loaded: viewModel.loaded.map(viewModel.displayName(of:)),
                        capacity: viewModel.capacity,
                        memory: viewModel.device.memory,
                        onUnloadAll: { isConfirmingUnloadAll = true }
                    )
                }
                if let notice = viewModel.notice {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.orange)
                            Text(notice)
                                .font(.subheadline)
                            Spacer(minLength: 0)
                            Button("Dismiss", systemImage: "xmark") { viewModel.notice = nil }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                ModelManagerSection(title: "In memory", rows: viewModel.loadedRows, actions: actions)
                ModelManagerSection(title: "Downloaded", rows: viewModel.downloadedRows, actions: actions)
                ModelManagerSection(title: "Not downloaded", rows: viewModel.notDownloadedRows, actions: actions)
                // Leftover tokenizer files alone don't count as a download.
                if hasDownloads {
                    Section {
                        LabeledContent {
                            Text(Format.bytes(viewModel.totalDownloadBytes))
                                .font(.headline)
                                .foregroundStyle(.blue)
                        } label: {
                            Label {
                                Text("Downloaded models")
                            } icon: {
                                Image(systemName: "internaldrive.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(.blue.gradient, in: .rect(cornerRadius: 7))
                            }
                        }
                        Button(role: .destructive) {
                            isConfirmingDeleteAll = true
                        } label: {
                            Label {
                                Text("Delete All Downloads")
                                    .foregroundStyle(.red)
                            } icon: {
                                Image(systemName: "trash.fill")
                                    .foregroundStyle(.white)
                                    .frame(width: 28, height: 28)
                                    .background(.red.gradient, in: .rect(cornerRadius: 7))
                            }
                        }
                    } header: {
                        Text("Storage")
                    } footer: {
                        Text("Downloaded models load without a network connection.")
                    }
                }
            }
            .readableContentWidth(760)
            // A solid edge above the tab bar, so rows don't show through it.
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .navigationTitle("Models")
            // The same title row as Chats and Benchmark.
            .toolbarTitleDisplayMode(.inlineLarge)
            .sheet(item: $settingsRow) { row in
                ModelSettingsSheet(
                    model: row.model,
                    temperature: viewModel.temperature(for: row),
                    contextWindow: viewModel.contextWindow(for: row),
                    sampling: viewModel.sampling(for: row),
                    isLoaded: row.isLoaded
                ) { temperature, tokens, sampling in
                    viewModel.setSettings(temperature: temperature, contextWindow: tokens, sampling: sampling, for: row)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort by Size", selection: $viewModel.sort) {
                            ForEach(ModelSort.allCases, id: \.self) { sort in
                                Text(sort.title).tag(sort)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .task { await viewModel.refresh() }
            .refreshable { await viewModel.refresh() }
            .alert(
                "Unload \(viewModel.loaded.count == 1 ? "1 model" : "\(viewModel.loaded.count) models") from memory?",
                isPresented: $isConfirmingUnloadAll
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Unload All") { Task { await viewModel.unloadAll() } }
            } message: {
                Text("They stay downloaded and load again when used. A reply or benchmark that's running stops.")
            }
            .alert(deleteTitle, isPresented: $isConfirmingDelete) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive, action: deletePending)
            }
            .alert(
                "Delete all downloads (\(Format.bytes(viewModel.totalDownloadBytes)))?",
                isPresented: $isConfirmingDeleteAll
            ) {
                Button("Cancel", role: .cancel) {}
                Button("Delete All", role: .destructive, action: deleteAll)
            }
            .problemAlert($viewModel.problem) { _ in viewModel.retry() }
            .alert("Couldn't Delete", isPresented: $viewModel.errorMessage.isPresent) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    /// Any model downloaded, or partly downloaded.
    private var hasDownloads: Bool {
        viewModel.rows.contains { $0.download.bytes > 0 }
    }

    private var actions: ModelManagerRow.Actions {
        ModelManagerRow.Actions(
            download: viewModel.download,
            cancel: viewModel.cancel,
            load: viewModel.load,
            unload: { row in Task { await viewModel.unload(row) } },
            startChat: viewModel.startChat,
            delete: confirmDelete,
            settings: { settingsRow = $0 }
        )
    }

    private var deleteTitle: String {
        guard let row = pendingDelete else { return "Delete download?" }
        return "Delete \(row.model.displayName) (\(Format.bytes(row.download.bytes)))?"
    }

    private func confirmDelete(_ row: ModelManagerViewModel.Row) {
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
}

#Preview {
    ModelManagerView(viewModel: .preview)
}
