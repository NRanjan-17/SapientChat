import SwiftUI

/// What's in memory now: a gauge of memory used against what iOS allows,
/// the loaded-model slots, and the loaded models' names.
struct MemorySummarySection: View {
    let loaded: [String]
    let capacity: Int
    let memory: MemoryStatus
    var onUnloadAll: (() -> Void)?

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    IconText("Memory", systemImage: "memorychip")
                        .font(.headline)
                    Spacer()
                    if let used = memory.footprintBytes {
                        Text("\(Format.bytes(used)) used")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(pressureColor)
                    }
                }
                if let fraction = usedFraction {
                    VStack(alignment: .leading, spacing: 6) {
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule()
                                    .fill(pressureColor)
                                    .frame(width: max(8, proxy.size.width * fraction))
                            }
                        }
                        .frame(height: 10)
                        if let available = memory.availableBytes {
                            Text("iOS allows \(Format.bytes(available)) more")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                HStack(spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(0..<capacity, id: \.self) { slot in
                            Capsule()
                                .fill(slot < loaded.count ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(.tertiarySystemFill)))
                                .frame(width: 18, height: 8)
                        }
                    }
                    Text("\(loaded.count) of \(capacity) models loaded")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !loaded.isEmpty {
                    FlowChips(items: loaded)
                }
                if let onUnloadAll {
                    Button("Unload All Models", systemImage: "eject", role: .destructive, action: onUnloadAll)
                        .font(.subheadline)
                        .buttonStyle(.borderless)
                        .disabled(loaded.isEmpty)
                }
            }
            .padding(.vertical, 6)
        } footer: {
            Text("Up to \(capacity) models stay loaded, so switching between their chats is instant. Loading another releases the one used least recently.")
        }
    }

    /// Share of the app's allowance in use; nil without a known limit.
    private var usedFraction: Double? {
        guard let used = memory.footprintBytes, let available = memory.availableBytes else { return nil }
        let total = Double(used) + Double(available)
        return total > 0 ? min(1, Double(used) / total) : nil
    }

    private var pressureColor: Color {
        switch usedFraction ?? 0 {
        case ..<0.85: .accentColor
        default: .orange
        }
    }
}

/// Loaded model names as chips, wrapping onto new lines.
private struct FlowChips: View {
    let items: [String]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { name in
            Chip(name, color: .accentColor)
        }
    }
}
