import SwiftUI

/// A titled group of manager rows; hidden when empty.
struct ModelManagerSection: View {
    let title: String
    let rows: [ModelManagerViewModel.Row]
    let actions: ModelManagerRow.Actions

    var body: some View {
        if !rows.isEmpty {
            Section(title) {
                ForEach(rows) { row in
                    ModelManagerRow(row: row, actions: actions)
                }
            }
        }
    }
}
