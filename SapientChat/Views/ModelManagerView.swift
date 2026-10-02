import SwiftUI

/// Download models ahead of time, load up to two into memory, unload,
/// delete, and start a chat with a model that's already loaded.
struct ModelManagerView: View {
    @Bindable var viewModel: ModelManagerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var pendingDelete: ModelManagerViewModel.Row?
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDeleteAll = false

    var body: some View {
        NavigationStack {
            List {
                MemorySummarySection(
                    loaded: viewModel.loaded.map(viewModel.displayName(of:)),
                    capacity: viewModel.capacity,
                    memory: viewModel.device.memory
                )
                ModelManagerSection(title: "In memory", rows: viewModel.loadedRows, actions: actions)
                ModelManagerSection(title: "Models", rows: viewModel.otherRows, actions: actions)
                Section {
                    LabeledContent("Downloaded", value: Format.bytes(viewModel.totalDownloadBytes))
                    Button("Delete All Downloads", systemImage: "trash", role: .destructive) {
                        isConfirmingDeleteAll = true
                    }
                    .disabled(viewModel.totalDownloadBytes == 0)
                } footer: {
                    Text("Downloaded models load without a network connection.")
                }
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
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
            delete: confirmDelete
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

    private func close() {
        dismiss()
    }
}

#Preview {
    ModelManagerView(viewModel: .preview)
}
