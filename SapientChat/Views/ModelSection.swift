import SwiftUI

/// A titled group of model rows; hidden when empty.
struct ModelSection: View {
    let title: String
    var footer: String?
    let rows: [ModelSelectorViewModel.Row]
    let canSelect: Bool
    let onSelect: (ModelSelectorViewModel.Row) -> Void
    let onDelete: (ModelSelectorViewModel.Row) -> Void

    var body: some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    ModelRow(row: row, canSelect: canSelect, onSelect: onSelect)
                        .swipeActions {
                            if row.download.isDownloaded {
                                Button("Delete Download", systemImage: "trash", role: .destructive) { onDelete(row) }
                            }
                        }
                }
            } header: {
                Text(title)
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }
}
