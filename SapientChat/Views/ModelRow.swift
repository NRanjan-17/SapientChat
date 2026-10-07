import SwiftUI

/// One model in a chat's model picker: colored tile, name, spec chips and
/// download state, with a checkmark on the chat's current model.
struct ModelRow: View {
    let row: ModelSelectorViewModel.Row
    let canSelect: Bool
    let onSelect: (ModelSelectorViewModel.Row) -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                ModelTile(model: row.model, isLoaded: row.isLoaded, size: 40)
                VStack(alignment: .leading, spacing: 5) {
                    Text(row.model.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    ModelSpecChips(model: row.model)
                    status
                        .font(.caption)
                }
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                Spacer(minLength: 8)
                if row.isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(row.model.tint)
                        .accessibilityLabel("Selected")
                }
            }
            .padding(.vertical, 4)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!canSelect)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var status: some View {
        if !row.fits {
            IconText("Needs more memory than iOS allows now", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if row.isLoaded {
            IconText("In memory", systemImage: "memorychip.fill")
                .foregroundStyle(.green)
        } else {
            switch row.download {
            case .downloaded(let bytes):
                IconText("Downloaded · \(Format.bytes(bytes))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            case .partial(let bytes):
                IconText("Paused at \(Format.bytes(bytes)) · resumes when used", systemImage: "arrow.down.circle.dotted")
                    .foregroundStyle(.orange)
            case .notDownloaded:
                IconText("Downloads when first used", systemImage: "arrow.down.circle")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func select() {
        onSelect(row)
    }
}
