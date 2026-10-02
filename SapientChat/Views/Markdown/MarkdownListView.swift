import SwiftUI

/// A bulleted or numbered list with hanging indents.
struct MarkdownListView: View {
    let ordered: Bool
    let start: Int
    let items: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(start + index)." : "•")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(InlineMarkdown.attributed(item))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
