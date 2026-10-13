// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

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
                // One line when it fits; two at large text sizes.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Spacer()
                        usedText
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        title
                        usedText
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
                            Text("\(Format.bytes(available)) more is free for models")
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
                    .accessibilityElement()
                    .accessibilityLabel("\(loaded.count) of \(capacity) models loaded")
                    Spacer(minLength: 8)
                    if let onUnloadAll {
                        // Not destructive: the models stay downloaded.
                        Button("Unload All", systemImage: "eject", action: onUnloadAll)
                            .font(.subheadline)
                            .buttonStyle(.borderless)
                            .frame(minHeight: 44)
                            .disabled(loaded.isEmpty)
                            .accessibilityLabel("Unload All Models")
                    }
                }
            }
            .padding(.vertical, 6)
        } footer: {
            Text("Up to \(capacity) models stay loaded, so switching between their chats is instant. Loading another releases the one used least recently.")
        }
    }

    private var title: some View {
        IconText("In Memory", systemImage: "memorychip")
            .font(.headline)
            .fixedSize()
    }

    /// The app's own memory plus its loaded models.
    @ViewBuilder private var usedText: some View {
        if let used = memory.residentBytes {
            Text("Sapient is using \(Format.bytes(used))")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(pressureColor)
        }
    }

    /// Share of the app's allowance in use; nil without a known limit.
    private var usedFraction: Double? {
        guard let used = memory.residentBytes, let available = memory.availableBytes else { return nil }
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
