import Foundation

// Self-contained sample data for SwiftUI previews.

nonisolated extension ChatMessage {
    static let samples: [ChatMessage] = [
        ChatMessage(role: .user, text: "What can you do offline?"),
        ChatMessage(role: .assistant, text: "Everything in this chat runs on your device, so I work without a network connection once the model is downloaded."),
        ChatMessage(role: .user, text: "Nice. Keep answers short."),
    ]
}

nonisolated extension PhoneModel {
    static let samples: [PhoneModel] = [
        PhoneModel(alias: "smollm2-135m-q4", params: "135M Q4_K_M", billions: 0.135),
        PhoneModel(alias: "qwen2.5-0.5b-q4", params: "0.5B Q4_K_M", billions: 0.5),
        PhoneModel(alias: "llama3.2-1b-q4", params: "1B Q4_K_M", billions: 1),
    ]
}

extension ChatViewModel {
    static var preview: ChatViewModel {
        ChatViewModel(
            chatService: PreviewChatService(),
            catalog: PreviewModelCatalog(),
            thermalService: PreviewThermalService(),
            messages: ChatMessage.samples
        )
    }

    static var emptyPreview: ChatViewModel {
        ChatViewModel(
            chatService: PreviewChatService(),
            catalog: PreviewModelCatalog(),
            thermalService: PreviewThermalService()
        )
    }
}
