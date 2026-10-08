// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import PDFKit
import Testing
@testable import SapientChat

@MainActor
struct PDFExportTests {
    let device = DeviceInfo(model: "iPhone16,2", system: "iOS 27.0.1", isSimulator: false)

    @Test func benchmarkReportIsAReadablePDF() throws {
        let url = try PDFExporter.export(
            BenchmarkReportView(result: .sample, device: device, date: .now),
            fileName: "test-benchmark-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let document = try #require(PDFDocument(url: url))
        #expect(document.pageCount == 1)
        let text = try #require(document.string)
        #expect(text.contains("smollm2-1.7b-q4"))
        #expect(text.contains("\(Format.rate(BenchmarkResult.sample.meanDecodeTokensPerSecond)) tok/s"), "the mean decode rate is in the report")
        #expect(text.contains("iPhone16,2"))
    }

    @Test func comparisonReportIncludesBothModels() throws {
        let results = [
            ModelComparison(model: "a", answer: "Answer A", benchmark: .sample),
            ModelComparison(model: "b", answer: "Answer B", benchmark: .sample),
        ]
        let url = try PDFExporter.export(
            CompareReportView(results: results, names: ["small", "large"], prompt: "Why is the sky blue?",
                              decodeDifferencePercent: 12.5, device: device, date: .now),
            fileName: "test-compare-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: url) }

        let text = try #require(PDFDocument(url: url)?.string)
        #expect(text.contains("small vs large"))
        #expect(text.contains("Answer B"))
        #expect(text.contains("12.5% faster"))
    }

    @Test func fileNamesAreSafe() {
        let name = PDFExporter.fileName("Benchmark", models: ["a/b"], date: Date(timeIntervalSince1970: 0))
        #expect(name.hasPrefix("SAPIENT Benchmark – a/b – 1970-01-01"))
    }
}
