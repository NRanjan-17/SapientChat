// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Canned `ChatService` for SwiftUI previews: no download, no engine.
nonisolated struct PreviewChatService: ChatService {
    func load(model: String) async throws -> String {
        "preview"
    }

    func details(model: String) async -> LoadedModelDetails? {
        LoadedModelDetails(backend: "preview", contextLength: 3072, loadTimeMs: 1_840)
    }

    func loadedModels() async -> [String] {
        []
    }

    func unload(model: String) async {}

    func unloadAll() async {}

    func reply(to history: [ChatMessage], model: String) async throws -> AsyncThrowingStream<String, any Error> {
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
