import Foundation

/// One request the API server answered, as saved in the request log: what
/// was asked, what came back, and how fast. Prompt, reply and bodies are
/// left out when the user turns off "Save prompts and replies".
nonisolated struct RequestLogEntry: Identifiable, Equatable, Sendable, Codable {
    struct Message: Equatable, Sendable, Codable {
        /// "system", "user" or "assistant".
        let role: String
        let text: String
    }

    /// Longest request or response body kept, in characters.
    static let maxBodyCharacters = 64 * 1024

    var id = UUID()
    var date: Date
    var method: String
    var path: String
    var status = 0
    /// The app that handed the request over by URL; nil for network clients.
    var source: String?
    var model: String?
    var durationMs: Int?
    /// The prompt: chat history, or a completion's prompt as one user message.
    var messages: [Message] = []
    var reply: String?
    var tokens: Int?
    var tokensPerSecond: Double?
    var timeToFirstTokenMs: Int?
    var error: String?
    var requestBody: String?
    var responseBody: String?

    /// The last user message, for the list.
    var promptPreview: String? {
        messages.last { $0.role == "user" }?.text
    }

    /// Without the prompt, reply and bodies: only what happened, not what was said.
    func withoutContent() -> RequestLogEntry {
        var entry = self
        entry.messages = []
        entry.reply = nil
        entry.requestBody = nil
        entry.responseBody = nil
        return entry
    }

    /// A body as text, cut to `maxBodyCharacters`; nil when empty.
    static func text(of body: Data) -> String? {
        guard !body.isEmpty else { return nil }
        let text = String(decoding: body, as: UTF8.self)
        guard text.count > maxBodyCharacters else { return text }
        return String(text.prefix(maxBodyCharacters)) + "\n… (cut at \(maxBodyCharacters / 1024) KB)"
    }
}
