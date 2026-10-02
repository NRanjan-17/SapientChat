import SwiftUI

/// Run/Cancel plus what the comparison is doing right now.
struct CompareRunSection: View {
    let phase: CompareViewModel.Phase
    let canRun: Bool
    let sameModel: Bool
    let onRun: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Section {
            switch phase {
            case .running(let step):
                HStack {
                    ProgressView()
                    Text(step)
                }
                Button("Cancel", role: .cancel, action: onCancel)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                runButton
            case .idle, .finished:
                runButton
            }
        } footer: {
            if sameModel {
                Text("Pick two different models.")
            }
        }
    }

    private var runButton: some View {
        Button("Run Comparison", systemImage: "play.fill", action: onRun)
            .disabled(!canRun)
    }
}
