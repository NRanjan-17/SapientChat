import SwiftUI

/// Download models ahead of time, load up to four into memory, unload,
/// delete, and start a chat with a model that's already loaded.
struct ModelManagerView: View {
    @Bindable var viewModel: ModelManagerViewModel
    @State private var pendingDelete: ModelManagerViewModel.Row?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDeleteAll = false
    @State private var contextWindowRow: ModelManagerViewModel.Row?

    var body: some View {
        NavigationStack {
            List {
                MemorySummarySection(
                    loaded: viewModel.loaded.map(viewModel.displayName(of:)),
                    capacity: viewModel.capacity,
                    memory: viewModel.device.memory
                )
                Section {
                    LabeledContent {
                        Text(viewModel.totalDownloadBytes == 0 ? "None" : Format.bytes(viewModel.totalDownloadBytes))
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
                        } icon: {
                            Image(systemName: "trash.fill")
                                .foregroundStyle(.white)
                                .frame(width: 28, height: 28)
                                .background(.red.gradient, in: .rect(cornerRadius: 7))
                        }
                    }
                    .disabled(viewModel.totalDownloadBytes == 0)
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Downloaded models load without a network connection.")
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
            }
            .navigationTitle("Models")
            .sheet(item: $contextWindowRow) { row in
                ContextWindowSheet(
                    model: row.model,
                    current: viewModel.contextWindow(for: row),
                    isLoaded: row.isLoaded
                ) { tokens in
                    viewModel.setContextWindow(tokens, for: row)
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
            .alert("Model", isPresented: $viewModel.errorMessage.isPresent) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
        }
    }

    private var actions: ModelManagerRow.Actions {
        ModelManagerRow.Actions(
            download: viewModel.download,
            cancel: viewModel.cancel,
            load: viewModel.load,
            unload: { row in Task { await viewModel.unload(row) } },
            startChat: viewModel.startChat,
            delete: confirmDelete,
            contextWindow: { contextWindowRow = $0 }
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
