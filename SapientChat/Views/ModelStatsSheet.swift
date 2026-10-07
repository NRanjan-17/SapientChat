import SwiftUI

/// The chat's model at a glance: what it is and how it runs on this
/// device, plus speed averages over this chat's replies.
struct ModelStatsSheet: View {
    let viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ModelStatsModelSection(
                    model: viewModel.model,
                    name: viewModel.modelName,
                    details: viewModel.modelDetails
                )
                ModelStatsDeviceSection(device: viewModel.device, loadedModels: viewModel.loadedModelNames)
                ModelStatsChatSection(summary: viewModel.chatSummary, last: viewModel.lastReplyStats)
            }
            .navigationTitle("Model Stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: close)
                }
            }
            .task { await viewModel.refreshModelDetails() }
            .refreshable { await viewModel.refreshModelDetails() }
        }
        .presentationDetents([.medium, .large])
    }

    private func close() {
        dismiss()
    }
}
