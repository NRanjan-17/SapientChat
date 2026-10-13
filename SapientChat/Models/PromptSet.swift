// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import SwiftData

/// A saved list of prompts to run against one or more models, with the
/// answers from its latest runs: a small regression suite for prompts.
nonisolated struct PromptSet: Identifiable, Equatable, Sendable, Codable {
    /// One model's answer to one prompt.
    struct Answer: Identifiable, Equatable, Sendable, Codable {
        var id = UUID()
        var prompt: String
        var model: String
        var reply: String
        var tokens: Int
        var tokensPerSecond: Double?
        var firstTokenMs: Int?
        /// Why there is no reply, when the model couldn't load or failed.
        var error: String?
    }

    /// Every prompt answered by every picked model, once.
    struct Run: Identifiable, Equatable, Sendable, Codable {
        var id = UUID()
        var date: Date
        var models: [String]
        var maxTokens: Int
        var answers: [Answer]
        /// Stopped before every prompt was answered.
        var cancelled = false

        func answers(to prompt: String) -> [Answer] {
            answers.filter { $0.prompt == prompt }
        }
    }

    /// Runs kept per set; older ones are dropped.
    static let runLimit = 10

    var id = UUID()
    var name: String
    /// Sent before each prompt; empty for none.
    var systemPrompt = ""
    var prompts: [String]
    /// Newest first.
    var runs: [Run] = []

    /// Prompts with text, trimmed: what a run sends.
    var usablePrompts: [String] {
        prompts.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// The set a new install starts with.
    static let starter = PromptSet(name: "Quick Check", prompts: [
        "What is the capital of France? Answer in one word.",
        "Write a Swift function that returns the sum of an array of Ints.",
        "Summarize in one sentence: The cache keeps recently used models in memory so switching between chats is instant.",
        "Reply with a JSON object with the keys \"city\" and \"country\" for Tokyo.",
    ])

    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
    }
}

/// A saved `PromptSet`, stored as JSON like `RequestRecord`.
@Model
final class PromptSetRecord {
    var id: UUID
    var date: Date
    var payload: Data

    init(_ set: PromptSet, date: Date = .now) {
        id = set.id
        self.date = date
        payload = (try? JSONEncoder().encode(set)) ?? Data()
    }

    var set: PromptSet? {
        try? JSONDecoder().decode(PromptSet.self, from: payload)
    }
}

/// Where prompt sets are kept between launches.
protocol PromptSetStore: AnyObject {
    /// Oldest first, so a set keeps its place in the list.
    func sets() -> [PromptSet]
    /// Adds the set, or replaces the saved one with the same id.
    func save(_ set: PromptSet)
    func delete(_ id: UUID)
}

final class SwiftDataPromptSetStore: PromptSetStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func sets() -> [PromptSet] {
        let descriptor = FetchDescriptor<PromptSetRecord>(sortBy: [SortDescriptor(\.date)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.set)
    }

    func save(_ set: PromptSet) {
        let id = set.id
        let descriptor = FetchDescriptor<PromptSetRecord>(predicate: #Predicate { $0.id == id })
        if let record = (try? context.fetch(descriptor))?.first {
            record.payload = (try? JSONEncoder().encode(set)) ?? record.payload
        } else {
            context.insert(PromptSetRecord(set))
        }
        try? context.save()
    }

    func delete(_ id: UUID) {
        let descriptor = FetchDescriptor<PromptSetRecord>(predicate: #Predicate { $0.id == id })
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        try? context.save()
    }
}

/// Kept in memory only: previews and tests.
final class InMemoryPromptSetStore: PromptSetStore {
    private var stored: [PromptSet] = []

    func sets() -> [PromptSet] { stored }

    func save(_ set: PromptSet) {
        if let index = stored.firstIndex(where: { $0.id == set.id }) {
            stored[index] = set
        } else {
            stored.append(set)
        }
    }

    func delete(_ id: UUID) { stored.removeAll { $0.id == id } }
}
