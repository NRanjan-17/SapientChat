import SwiftUI

/// Shown while another app's request runs, with a way to cancel it.
struct HandoffBanner: View {
    let viewModel: HandoffViewModel

    var body: some View {
        switch viewModel.state {
        case .idle:
            EmptyView()
        case .running(let source, let path):
            card {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Request from \(source ?? "another app")")
                        .font(.subheadline.weight(.semibold))
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: viewModel.cancel)
                    .buttonStyle(.bordered)
            }
        case .failed(let message):
            card {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.subheadline)
                Spacer()
                Button("OK", action: viewModel.dismissError)
                    .buttonStyle(.bordered)
            }
        }
    }

    private func card(@ViewBuilder _ content: () -> some View) -> some View {
        HStack(spacing: 12, content: content)
            .padding(12)
            .background(.regularMaterial, in: .rect(cornerRadius: 16))
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
