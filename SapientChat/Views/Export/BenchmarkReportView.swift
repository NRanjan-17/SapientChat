// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// The printable report of one benchmark.
struct BenchmarkReportView: View {
    let result: BenchmarkResult
    let device: DeviceInfo
    let date: Date

    private var modelName: String {
        result.model.split(separator: "/").last.map(String.init) ?? result.model
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ReportHeader(title: "Benchmark", subtitle: modelName, device: device, date: date)

            ReportTable(title: "Results", columns: ["Metric", "Value"], rows: [
                ["Decode (mean)", "\(Format.rate(result.meanDecodeTokensPerSecond)) tok/s"],
                ["Decode (range)", "\(Format.rate(result.minDecodeTokensPerSecond)) – \(Format.rate(result.maxDecodeTokensPerSecond)) tok/s"],
                ["Time to first token", "\(result.meanTtftMs) ms"],
                ["Prefill", "\(Format.rate(result.meanPrefillTokensPerSecond)) tok/s"],
                ["Peak memory", result.peakFootprintBytes.map(Format.bytes) ?? "—"],
            ])

            ReportTable(title: "Runs", columns: ["Run", "Decode", "TTFT", "Tokens", "Memory"],
                        rows: (result.warmupRuns + result.runs).map { run in
                            [
                                run.isWarmup ? "Warm-up \(run.index)" : "Run \(run.index)",
                                "\(Format.rate(run.decodeTokensPerSecond)) tok/s",
                                "\(run.ttftMs) ms",
                                "\(run.tokens)\(run.hitEndOfTurn ? " (early stop)" : "")",
                                run.footprintBytes.map(Format.bytes) ?? "—",
                            ]
                        })

            ReportTable(title: "Setup", columns: ["", ""], rows: [
                ["Backend", result.backend],
                ["Weights", result.isMemoryMapped ? "Memory-mapped" : "In memory"],
                ["Context window", "\(result.contextLength) tokens"],
                ["Prompt / max tokens", "\(result.promptTokens) / \(result.maxTokens)"],
                ["Model load", "\(result.loadTimeMs) ms"],
                ["Thermal", "\(result.thermalStart) → \(result.thermalEnd)"],
                ["Engine", "SAPIENT \(result.engineVersion)"],
            ])

            Text("Method: \(result.method). Warm-up runs are excluded from the averages.\(result.cancelled ? " Cancelled before all runs finished." : "")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(40)
        .background(.white)
    }
}

#Preview {
    ScrollView {
        BenchmarkReportView(result: .sample, device: DeviceInfo(model: "iPhone16,2", system: "iOS 27.0.1", isSimulator: false), date: .now)
    }
}
