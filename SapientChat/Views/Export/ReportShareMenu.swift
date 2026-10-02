import SwiftUI

/// "Share" menu with the PDF report and the raw JSON. The PDF is rendered
/// when the menu appears (and again if the results change).
struct ReportShareMenu<Report: View>: View {
    let title: String
    let fileName: String
    let json: String
    let report: () -> Report

    @State private var pdf: URL?

    var body: some View {
        Menu(title, systemImage: "square.and.arrow.up") {
            if let pdf {
                ShareLink(item: pdf) {
                    Label("Share PDF", systemImage: "doc.richtext")
                }
            }
            ShareLink(item: json, preview: SharePreview(fileName)) {
                Label("Share JSON", systemImage: "curlybraces")
            }
        }
        .task(id: json) { renderPDF() }
    }

    private func renderPDF() {
        pdf = try? PDFExporter.export(report(), fileName: fileName)
    }
}
