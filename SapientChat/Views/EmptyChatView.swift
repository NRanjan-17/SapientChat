import SwiftUI

/// A new chat: what runs it and a few prompts to start with.
struct EmptyChatView: View {
    let modelName: String
    let onSuggestion: (String) -> Void

    static let suggestions = [
        "Explain how a transformer model works, simply.",
        "Write a haiku about running AI on a phone.",
        "Give me three tips for a productive morning.",
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                ContentUnavailableView {
                    Label("Chat with \(modelName)", systemImage: "sparkles")
                } description: {
                    Text("Everything runs on this iPhone. Nothing you type leaves the device.")
                }
                VStack(spacing: 10) {
                    ForEach(Self.suggestions, id: \.self) { suggestion in
                        SuggestionButton(text: suggestion, onTap: onSuggestion)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.vertical)
        }
        .readableContentWidth(640)
    }
}

#Preview {
    EmptyChatView(modelName: "smollm2-135m-q4", onSuggestion: { _ in })
}
