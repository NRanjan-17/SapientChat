import SwiftUI

/// A fenced code block: monospaced, scrolls sideways instead of wrapping,
/// with its language and a Copy button.
struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc", action: copy)
                    .font(.caption)
                    .labelStyle(.titleAndIcon)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 12)
            Divider()
            ScrollView(.horizontal) {
                Text(code)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
                    .padding(12)
            }
            .scrollIndicators(.hidden)
        }
        .background(.background.secondary, in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12).strokeBorder(.separator, lineWidth: 0.5)
        }
        .sensoryFeedback(.success, trigger: copied) { _, new in new }
    }

    private func copy() {
        UIPasteboard.general.string = code
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }
}

#Preview {
    CodeBlockView(language: "swift", code: "let answer = 42\nprint(\"The answer is \\(answer), a fairly long line that scrolls\")")
        .padding()
}
