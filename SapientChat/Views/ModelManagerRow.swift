import SwiftUI

/// One model in the manager: what it is, its state (not downloaded,
/// downloading with progress, downloaded, loading, in memory) and the
/// actions that make sense for that state.
struct ModelManagerRow: View {
    struct Actions {
        let download: (ModelManagerViewModel.Row) -> Void
        let cancel: (ModelManagerViewModel.Row) -> Void
        let load: (ModelManagerViewModel.Row) -> Void
        let unload: (ModelManagerViewModel.Row) -> Void
        let startChat: (ModelManagerViewModel.Row) -> Void
        let delete: (ModelManagerViewModel.Row) -> Void
    }

    let row: ModelManagerViewModel.Row
    let actions: Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.model.displayName)
                    .font(.headline)
                Spacer()
                ModelStatusBadge(row: row)
            }
            Text("\(row.model.params.split(separator: " ").first.map(String.init) ?? row.model.params) · \(row.model.format) · ≈\(Format.bytes(row.model.estimatedMemoryBytes)) memory")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            switch row.activity {
            case .downloading(let progress):
                DownloadProgressView(progress: progress)
            case .loading:
                Label("Loading into memory…", systemImage: "memorychip")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case nil:
                EmptyView()
            }

            ModelManagerButtons(row: row, actions: actions)
        }
        .padding(.vertical, 4)
        .swipeActions {
            if row.download.bytes > 0 && row.activity == nil {
                Button("Delete Download", systemImage: "trash", role: .destructive) { actions.delete(row) }
            }
        }
        .animation(.smooth, value: row.activity)
    }
}
