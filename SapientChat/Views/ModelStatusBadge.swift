import SwiftUI

/// "In memory" / "Downloaded" / "Partial" / "Too large" capsule.
struct ModelStatusBadge: View {
    let row: ModelManagerViewModel.Row

    private var label: (text: String, symbol: String, style: AnyShapeStyle)? {
        if row.isLoaded { return ("In memory", "memorychip.fill", AnyShapeStyle(.green)) }
        switch row.download {
        case .downloaded: return ("Downloaded", "checkmark.circle.fill", AnyShapeStyle(.tint))
        case .partial: return ("Partial", "arrow.down.circle", AnyShapeStyle(.orange))
        case .notDownloaded: return row.fits ? nil : ("Too large", "exclamationmark.triangle.fill", AnyShapeStyle(.secondary))
        }
    }

    var body: some View {
        if let label {
            Label(label.text, systemImage: label.symbol)
                .font(.caption.bold())
                .foregroundStyle(label.style)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(label.style.opacity(0.12), in: .capsule)
        }
    }
}
