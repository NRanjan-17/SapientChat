import SwiftUI

/// One metric for both models: "Decode   A 27.4 tok/s   B 31.0 tok/s".
struct CompareMetricRow: View {
    let title: String
    let a: String?
    let b: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            HStack(alignment: .top) {
                CompareValue(side: "A", value: a)
                CompareValue(side: "B", value: b)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
