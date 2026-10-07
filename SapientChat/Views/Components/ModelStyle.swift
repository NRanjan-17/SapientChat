import SwiftUI

extension PhoneModel {
    /// The model family, e.g. "smollm2" or "qwen2.5".
    var family: String {
        displayName.split(separator: "-").first.map(String.init) ?? displayName
    }

    /// A color per family, so models are easy to tell apart at a glance.
    var tint: Color {
        let family = family.lowercased()
        return if family.hasPrefix("smollm") {
            .purple
        } else if family.hasPrefix("gemma") {
            .blue
        } else if family.hasPrefix("qwen") {
            .orange
        } else if family.hasPrefix("llama") {
            .teal
        } else if family.hasPrefix("phi") {
            .green
        } else if family.hasPrefix("mistral") {
            .red
        } else {
            .indigo
        }
    }

    /// "360M" / "1.5B".
    var sizeText: String {
        params.split(separator: " ").first.map(String.init) ?? params
    }

    /// Short storage format for a chip: "4-bit", "8-bit", "Full".
    var formatChip: (text: String, color: Color) {
        if params.contains("Q4") {
            ("4-bit", .green)
        } else if params.contains("Q8") {
            ("8-bit", .mint)
        } else {
            ("Full", .orange)
        }
    }
}

/// The model's colored tile, with a memory-chip badge while it's in memory.
struct ModelTile: View {
    let model: PhoneModel
    var isLoaded = false
    var size: CGFloat = 44

    var body: some View {
        Image(systemName: "square.stack.3d.up")
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(model.tint.gradient, in: .rect(cornerRadius: size * 0.26))
            .overlay(alignment: .bottomTrailing) {
                if isLoaded {
                    Image(systemName: "memorychip.fill")
                        .font(.system(size: size * 0.24, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(size * 0.08)
                        .background(.green, in: .circle)
                        .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                        .offset(x: size * 0.12, y: size * 0.12)
                }
            }
            .accessibilityHidden(true)
    }
}

/// A small tinted capsule: "360M", "4-bit", "1.0 GB RAM".
struct Chip: View {
    let text: String
    var color: Color = .secondary

    init(_ text: String, color: Color = .secondary) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: .capsule)
    }
}

/// Size, format and memory chips for a model.
struct ModelSpecChips: View {
    let model: PhoneModel

    var body: some View {
        HStack(spacing: 5) {
            Chip(model.sizeText, color: model.tint)
            Chip(model.formatChip.text, color: model.formatChip.color)
            Chip("\(Format.compactBytes(model.estimatedMemoryBytes)) RAM")
        }
    }
}

/// An icon and text with a tight, fixed gap (a plain `Label` spaces them
/// widely inside small fonts and buttons).
struct IconText: View {
    let symbol: String
    let text: String

    init(_ text: String, systemImage symbol: String) {
        self.text = text
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .imageScale(.small)
            Text(text)
        }
    }
}
