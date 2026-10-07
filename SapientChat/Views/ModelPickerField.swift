import SwiftUI

/// A model choice shown like a row of the chat's model picker (logo, name,
/// chips, download state); tapping it opens that same picker. Used by
/// Benchmark and Compare.
struct ModelPickerField: View {
    let title: String
    let selection: String
    /// Builds the picker: current pick, and what to do with a new one.
    let makeSelector: (String, @escaping (String) -> Void) -> ModelSelectorViewModel
    let onSelect: (String) -> Void

    /// Download/memory state of the models, for this row.
    @State private var info: ModelSelectorViewModel?
    @State private var picker: ModelSelectorViewModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let row = info?.rows.first(where: { $0.model.alias == selection }) {
                ModelRow(
                    row: ModelSelectorViewModel.Row(
                        model: row.model, download: row.download, fits: row.fits,
                        isSelected: false, isLoaded: row.isLoaded
                    ),
                    canSelect: true,
                    onSelect: { _ in open() }
                )
            } else {
                Button(selection, action: open)
            }
        }
        .accessibilityHint("Opens the model list")
        .task(id: selection) { await refresh() }
        .sheet(item: $picker, onDismiss: { Task { await refresh() } }) { picker in
            ModelSelectorView(viewModel: picker)
        }
    }

    private func refresh() async {
        let selector = makeSelector(selection) { _ in }
        await selector.refresh()
        info = selector
    }

    private func open() {
        picker = makeSelector(selection, onSelect)
    }
}
