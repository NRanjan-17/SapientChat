// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// Renders a SwiftUI report to a one-page PDF (A4 width, as tall as the
/// content) in the temporary directory, ready for `ShareLink`.
enum PDFExporter {
    enum ExportError: Error {
        case renderFailed
    }

    /// A4 width in points.
    static let pageWidth = 595.0

    static func export(_ report: some View, fileName: String) throws -> URL {
        let renderer = ImageRenderer(
            content: report
                .frame(width: pageWidth)
                .environment(\.colorScheme, .light)
        )
        let safeName = fileName.replacing("/", with: "-")
        let url = URL.temporaryDirectory.appending(path: "\(safeName).pdf")
        var rendered = false
        renderer.render { size, draw in
            var box = CGRect(origin: .zero, size: size)
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            rendered = true
        }
        guard rendered else { throw ExportError.renderFailed }
        return url
    }

    static func fileName(_ title: String, models: [String], date: Date) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        return "SAPIENT \(title) – \(models.joined(separator: " vs ")) – \(day)"
    }
}
