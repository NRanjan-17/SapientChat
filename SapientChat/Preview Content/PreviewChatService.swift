import Foundation

/// Canned `ChatService` for SwiftUI previews: no download, no engine.
nonisolated struct PreviewChatService: ChatService {
    func load(model: String) async throws -> String {
        "preview"
    }

    func loadedModel() async -> String? {
        nil
    }

    func unload() async {}

    func reply(to history: [ChatMessage]) async throws -> AsyncThrowingStream<String, any Error> {
        let words = "This is a canned **preview** reply, streamed one word at a time.".split(separator: " ")
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        let task = Task {
            for word in words {
                try? await Task.sleep(for: .milliseconds(80))
                continuation.yield(word + " ")
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return stream
    }
}
