import SwiftUI

/// One model: name, size and format, estimated memory, download state.
struct ModelRow: View {
    let row: ModelSelectorViewModel.Row
    let canSelect: Bool
    let onSelect: (ModelSelectorViewModel.Row) -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(row.model.displayName)
                            .font(.headline)
                        if row.isLoaded {
                            Text("Loaded")
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.15), in: .capsule)
                        }
                    }
                    Text("\(row.model.params.split(separator: " ").first.map(String.init) ?? row.model.params) · \(row.model.format) · ≈\(Format.bytes(row.model.estimatedMemoryBytes)) memory")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(downloadText, systemImage: row.download.isDownloaded ? "checkmark.icloud" : "icloud.and.arrow.down")
                        .font(.subheadline)
                        .foregroundStyle(row.download.isDownloaded ? .green : .secondary)
                }
                Spacer()
                if row.isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
        .accessibilityElement(children: .combine)
    }

    private var downloadText: String {
        switch row.download {
        case .downloaded(let bytes): "Downloaded · \(Format.bytes(bytes))"
        case .notDownloaded: "Downloads when first used"
        }
    }

    private func select() {
        onSelect(row)
    }
}
