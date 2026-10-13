// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// Prompt sets: saved lists of prompts, run against up to three models one
/// after the other, with every answer and its speed kept for comparing.
@Observable
final class PromptSetsViewModel {
    struct Progress: Equatable {
        var done: Int
        var total: Int
        /// What is running now, e.g. "qwen2.5-0.5b-q4 · prompt 2 of 4".
        var label: String

        var fraction: Double { total > 0 ? Double(done) / Double(total) : 0 }
    }

    static let maxModels = 3
    static let maxTokenChoices = [64, 128, 256, 512, 1024]

    private(set) var sets: [PromptSet]
    var selectedID: PromptSet.ID?
    /// Models every prompt is sent to, in order.
    private(set) var models: [String]
    /// Each answer stops after this many tokens, so a run stays short.
    var maxTokens = 128
    private(set) var progress: Progress?
    var alert: AppProblem?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let device: DeviceStatus
    @ObservationIgnored private let store: any PromptSetStore
    @ObservationIgnored private var task: Task<Void, Never>?

    init(services: AppServices, device: DeviceStatus, store: any PromptSetStore, initialModel: String) {
        self.services = services
        self.device = device
        self.store = store
        models = [initialModel]
        var saved = store.sets()
        if saved.isEmpty {
            store.save(.starter)
            saved = [.starter]
        }
        sets = saved
        selectedID = saved.first?.id
    }

    var selected: PromptSet? {
        sets.first { $0.id == selectedID }
    }

    var isRunning: Bool { progress != nil }

    var canRun: Bool {
        !isRunning && !models.isEmpty && selected?.usablePrompts.isEmpty == false
    }

    var canAddModel: Bool { models.count < Self.maxModels }

    func displayName(of alias: String) -> String {
        services.catalog.chatModels().first { $0.alias == alias }?.displayName
            ?? alias.split(separator: "/").last.map(String.init) ?? alias
    }

    // MARK: Editing

    func setModel(_ alias: String, at index: Int) {
        guard models.indices.contains(index), !isRunning else { return }
        models[index] = alias
    }

    /// Adds a model that isn't picked yet (the next in the catalog).
    func addModel() {
        guard canAddModel, !isRunning else { return }
        let catalog = services.catalog.chatModels().map(\.alias)
        models.append(catalog.first { !models.contains($0) } ?? models[0])
    }

    func removeModel(at index: Int) {
        guard models.count > 1, models.indices.contains(index), !isRunning else { return }
        models.remove(at: index)
    }

    @discardableResult
    func newSet() -> PromptSet {
        let set = PromptSet(name: "Prompt Set \(sets.count + 1)", prompts: [""])
        sets.append(set)
        store.save(set)
        selectedID = set.id
        return set
    }

    /// Saves an edited set. A blank name falls back to "Untitled".
    func save(_ set: PromptSet) {
        var set = set
        if set.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { set.name = "Untitled" }
        guard let index = sets.firstIndex(where: { $0.id == set.id }) else { return }
        sets[index] = set
        store.save(set)
    }

    func delete(_ set: PromptSet) {
        guard !isRunning else { return }
        sets.removeAll { $0.id == set.id }
        store.delete(set.id)
        if selectedID == set.id { selectedID = sets.first?.id }
    }

    // MARK: Running

    func run() {
        guard canRun, let set = selected else { return }
        let prompts = set.usablePrompts
        let models = models
        let limit = maxTokens
        progress = Progress(done: 0, total: prompts.count * models.count, label: "Starting…")
        task = Task { [weak self] in
            await self?.execute(setID: set.id, system: set.systemPrompt, prompts: prompts, models: models, limit: limit)
        }
    }

    /// Stops after the answer in flight; what was answered is kept.
    func cancel() {
        task?.cancel()
    }

    private func execute(setID: UUID, system: String, prompts: [String], models: [String], limit: Int) async {
        var run = PromptSet.Run(date: .now, models: models, maxTokens: limit, answers: [])
        var done = 0
        // Model by model, so each loads once.
        models: for alias in models {
            let name = displayName(of: alias)
            progress = Progress(done: done, total: prompts.count * models.count, label: "Loading \(name)…")
            do {
                _ = try await ModelPreparer(services: services, device: device).prepare(alias) { _ in }
            } catch {
                if error is CancellationError || Task.isCancelled { break models }
                let problem = AppProblem.current(error, model: name)
                for prompt in prompts {
                    run.answers.append(.init(prompt: prompt, model: alias, reply: "", tokens: 0, error: problem.title))
                }
                done += prompts.count
                continue
            }
            for (index, prompt) in prompts.enumerated() {
                if Task.isCancelled { break models }
                progress = Progress(
                    done: done, total: prompts.count * models.count,
                    label: "\(name) · prompt \(index + 1) of \(prompts.count)"
                )
                run.answers.append(await answer(prompt, system: system, model: alias, limit: limit))
                done += 1
            }
        }
        run.cancelled = Task.isCancelled
        if !run.answers.isEmpty, var set = sets.first(where: { $0.id == setID }) {
            set.runs.insert(run, at: 0)
            set.runs = Array(set.runs.prefix(PromptSet.runLimit))
            save(set)
        }
        device.refreshMemory()
        progress = nil
        task = nil
    }

    private func answer(_ prompt: String, system: String, model: String, limit: Int) async -> PromptSet.Answer {
        var history: [ChatMessage] = []
        let instructions = system.trimmingCharacters(in: .whitespacesAndNewlines)
        if !instructions.isEmpty { history.append(ChatMessage(role: .system, text: instructions)) }
        history.append(ChatMessage(role: .user, text: prompt))
        var result = PromptSet.Answer(prompt: prompt, model: model, reply: "", tokens: 0)
        let started = ContinuousClock.now
        var first: ContinuousClock.Instant?
        var last: ContinuousClock.Instant?
        do {
            for try await token in try await services.chat.reply(to: history, model: model) {
                let now = ContinuousClock.now
                if first == nil {
                    first = now
                    result.firstTokenMs = (now - started).milliseconds
                }
                last = now
                result.reply += token
                result.tokens += 1
                if result.tokens >= limit || Task.isCancelled { break }
            }
        } catch {
            if !(error is CancellationError) {
                result.error = AppProblem.current(error, model: displayName(of: model)).title
            }
        }
        if let first, let last, result.tokens > 1 {
            let seconds = Double((last - first).milliseconds) / 1000
            if seconds > 0 { result.tokensPerSecond = Double(result.tokens - 1) / seconds }
        }
        return result
    }
}
