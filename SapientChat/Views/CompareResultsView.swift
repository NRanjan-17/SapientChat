// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Both answers, then the numbers side by side.
struct CompareResultsView: View {
    let results: [ModelComparison]
    let names: [String]
    let prompt: String
    let decodeDifferencePercent: Double?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            // Wide screens: the two answers side by side.
            Section("Answers") {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(index == 0 ? "A" : "B") · \(names[index])")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            answer(result)
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        if index == 0 && results.count > 1 { Divider() }
                    }
                }
            }
        } else {
            ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                Section("\(index == 0 ? "A" : "B") · \(names[index])") {
                    answer(result)
                }
            }
        }

        if results.contains(where: { $0.benchmark != nil }) {
            Section {
                metric("Decode") { $0.benchmark.map { "\(Format.rate($0.meanDecodeTokensPerSecond)) tok/s" } }
                metric("First token") { $0.benchmark.map { "\($0.meanTtftMs) ms" } }
                metric("Prefill") { $0.benchmark.map { "\(Format.rate($0.meanPrefillTokensPerSecond)) tok/s" } }
                metric("Memory in use") { $0.memoryInUseBytes.map(Format.bytes) }
                metric("Load time") { $0.benchmark.map { "\($0.loadTimeMs) ms" } }
            } header: {
                Text("Numbers")
            } footer: {
                if let difference = decodeDifferencePercent {
                    Text("\(names[1]) decodes \(Format.rate(abs(difference)))% \(difference >= 0 ? "faster" : "slower") than \(names[0]).")
                }
            }
            if let json = exportText {
                Section {
                    ReportShareMenu(
                        title: "Share Results",
                        fileName: PDFExporter.fileName("Comparison", models: names, date: .now),
                        json: json
                    ) {
                        CompareReportView(
                            results: results, names: names, prompt: prompt,
                            decodeDifferencePercent: decodeDifferencePercent, device: .current(), date: .now
                        )
                    }
                }
            }
        }
    }

    private func answer(_ result: ModelComparison) -> some View {
        Text(result.answer.isEmpty ? "…" : result.answer)
            .textSelection(.enabled)
            .foregroundStyle(result.answer.isEmpty ? .secondary : .primary)
    }

    private func metric(_ title: String, _ value: (ModelComparison) -> String?) -> CompareMetricRow {
        CompareMetricRow(title: title, a: results.first.flatMap(value), b: results.dropFirst().first.flatMap(value))
    }

    private var exportText: String? {
        let finished = results.compactMap(\.benchmark)
        guard finished.count == results.count else { return nil }
        return "[\n" + finished.map { $0.jsonText() }.joined(separator: ",\n") + "\n]"
    }
}
