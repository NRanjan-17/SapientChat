import SwiftUI

/// Message field plus Send, or Stop while a reply is streaming.
struct ChatInputBar: View {
    @Binding var draft: String
    let isBusy: Bool
    let isGenerating: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    var body: some View {
        HStack(alignment: .bottom) {
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.roundedBorder)
                .disabled(isBusy)
                .onSubmit(onSend)

            if isGenerating {
                Button("Stop", systemImage: "stop.circle.fill", action: onStop)
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .frame(minWidth: 44, minHeight: 44)
            } else {
                Button("Send", systemImage: "arrow.up.circle.fill", action: onSend)
                    .labelStyle(.iconOnly)
                    .font(.title)
                    .frame(minWidth: 44, minHeight: 44)
                    .disabled(!canSend)
            }
        }
        .padding()
        .background(.bar)
    }
}

#Preview {
    @Previewable @State var draft = "Hello"
    ChatInputBar(draft: $draft, isBusy: false, isGenerating: false, canSend: true, onSend: {}, onStop: {})
}
