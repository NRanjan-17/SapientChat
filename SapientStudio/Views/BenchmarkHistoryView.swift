// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Past benchmarks, newest first, each with its change from the run before
/// it on the same model, device and compute.
struct BenchmarkHistoryView: View {
    let history: BenchmarkHistory
    @State private var isConfirmingClear = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(history.entries) { entry in
                    BenchmarkHistoryRow(entry: entry, change: history.change(for: entry))
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { history.delete(entry) }
                        }
                }
            }
            .overlay {
                if history.entries.isEmpty {
                    ContentUnavailableView(
                        "No benchmarks yet",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("Each finished benchmark is saved here, so you can see whether an engine or iOS update changed the speed.")
                    )
                }
            }
            .readableContentWidth(760)
            .navigationTitle("Benchmark History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ShareLink(item: history.exportJSON(), preview: SharePreview("Sapient benchmark history")) {
                            Label("Export as JSON", systemImage: "square.and.arrow.up")
                        }
                        Button("Clear History", systemImage: "trash", role: .destructive) { isConfirmingClear = true }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .disabled(history.entries.isEmpty)
                }
            }
            .alert("Clear benchmark history?", isPresented: $isConfirmingClear) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive, action: history.clear)
            } message: {
                Text("All \(history.entries.count) saved results are removed from this device.")
            }
        }
    }
}

/// One past benchmark: model, speed and its change, first-token time, and
/// what it ran on.
struct BenchmarkHistoryRow: View {
    let entry: BenchmarkHistoryEntry
    /// Decode speed against the comparable run before it; nil without one.
    let change: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.modelName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(Format.rate(entry.result.meanDecodeTokensPerSecond)) tok/s")
                    .font(.headline)
                    .monospacedDigit()
            }
            HStack(alignment: .firstTextBaseline) {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                Spacer(minLength: 8)
                if let change {
                    Text(Self.changeText(change))
                        .foregroundStyle(Self.isNoise(change) ? AnyShapeStyle(.secondary) : change > 0 ? AnyShapeStyle(.green) : AnyShapeStyle(.orange))
                        .monospacedDigit()
                } else {
                    Text("First run")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            Text(details)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var details: String {
        var parts = [
            "First token \(entry.result.meanTtftMs) ms",
            ChatViewModel.hardware(entry.result.backend),
            "SAPIENT \(entry.result.engineVersion)",
            entry.system,
        ]
        if entry.result.isSimulator { parts.append("Simulator") }
        return parts.joined(separator: " · ")
    }

    /// Within 3% either way is run-to-run variation, not a change.
    static func isNoise(_ change: Double) -> Bool {
        abs(change) < 0.03
    }

    static func changeText(_ change: Double) -> String {
        let percent = (change * 100).formatted(.number.precision(.fractionLength(0)).sign(strategy: .always()))
        return "\(percent)% vs last run"
    }
}
