import SwiftUI

/// One tappable starter prompt.
struct SuggestionButton: View {
    let text: String
    let onTap: (String) -> Void

    var body: some View {
        Button(action: tap) {
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(.fill.tertiary, in: .rect(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    private func tap() {
        onTap(text)
    }
}
