// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// State and actions for one conversation. Main-actor isolated (the target
/// default). The transcript lives in SwiftData; `messages` mirrors it so a
/// streaming reply can update the UI on every token without hitting disk.
@Observable
final class ChatViewModel {
    let conversation: Conversation
    private(set) var messages: [ChatMessage]
    private(set) var status: ChatStatus = .idle
    /// A problem to show as a pop-up; cleared when it's dismissed.
    var alert: AppProblem?
    private(set) var backendLabel: String?
    /// Speed of the reply streaming right now (≈ tok/s), updated twice a second.
    private(set) var liveTokensPerSecond: Double?
    /// Engine details of this chat's model, for the Model Stats sheet.
    private(set) var modelDetails: LoadedModelDetails?
    /// Display names of the models in memory, most recently used first.
    private(set) var loadedModelNames: [String] = []
    /// Older messages left out of the last request because the chat has
    /// outgrown the model's context window.
    private(set) var droppedFromContext = 0
    /// The last reply was cut off because it kept repeating itself.
    private(set) var stoppedRepeating = false
    var draft = ""

    @ObservationIgnored private let services: AppServices
    /// Leaving the app interrupted the prompt before the model was ready.
    @ObservationIgnored private var resendsOnReturn = false
    @ObservationIgnored private let store: any ConversationStore
    /// Shared app-wide state (memory, thermal) owned by the chat list.
    @ObservationIgnored let device: DeviceStatus
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    /// The stored reply of the turn in flight; Clear/Stop compare against it.
    @ObservationIgnored private var currentReplyID: UUID?
    /// How often a streaming reply is written to disk.
    @ObservationIgnored private let saveInterval: Duration

    init(
        conversation: Conversation,
        services: AppServices,
        store: any ConversationStore,
        device: DeviceStatus,
        saveInterval: Duration = .seconds(1)
    ) {
        self.conversation = conversation
        self.services = services
        self.store = store
        self.device = device
        self.saveInterval = saveInterval
        messages = conversation.orderedMessages.map(\.chatMessage)
    }

    var model: PhoneModel? {
        services.catalog.chatModels().first { $0.alias == conversation.modelAlias }
    }

    var modelName: String {
        model?.displayName ?? conversation.modelAlias
    }

    /// Whether this chat's model is on the device; nil for an unknown model.
    var modelDownload: ModelDownload? {
        model.map { services.storage.download(forRepo: $0.repoId) }
    }

    /// Sending now starts a download the user hasn't seen the size of.
    var needsDownloadToSend: Bool {
        guard let modelDownload else { return false }
        return !modelDownload.isDownloaded
    }

    var isBusy: Bool {
        switch status {
        case .idle, .failed: false
        case .downloading, .loading, .generating: true
        }
    }

    var isGenerating: Bool { status == .generating }

    var canSend: Bool {
        !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Regenerate the last reply, or retry when the last message got no reply.
    var canRegenerate: Bool {
        !isBusy && !messages.isEmpty
    }

    var statusText: String {
        let thermal = device.thermal.label.map { " · \($0)" } ?? ""
        return switch status {
        case .idle:
            // Short: memory and thermal detail live in Model Stats.
            [modelName, backendLabel.map(Self.hardware)].compactMap { $0 }.joined(separator: " · ")
        case .downloading(let model, let progress): "Downloading \(model) · \(progress.text)"
        case .loading(let model): "Loading \(model) into memory…"
        case .generating: "Generating" + (liveTokensPerSecond.map { " · \(Format.rate($0)) tok/s" } ?? "…") + thermal
        case .failed(let problem): problem.title
        }
    }

    /// "CPU + GPU", "GPU" or "CPU" from an engine label like
    /// "wgpu (Apple A14 GPU (Metal))" or "hybrid: prompt on … · generation on cpu".
    nonisolated static func hardware(_ backend: String) -> String {
        let lower = backend.lowercased()
        if lower.hasPrefix("hybrid") { return "CPU + GPU" }
        return lower.contains("cpu") ? "CPU" : (lower.contains("gpu") || lower.contains("metal")) ? "GPU" : backend
    }

    // MARK: Actions

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }
        draft = ""
        if conversation.title == Conversation.untitled {
            conversation.title = Self.title(from: prompt)
        }
        let user = store.append(.user, text: prompt, to: conversation)
        messages.append(user.chatMessage)
        startReply()
    }

    /// Replaces the last reply with a new one, or answers the last message
    /// if it never got a reply (e.g. the model failed to load).
    func regenerate() {
        guard canRegenerate else { return }
        if let last = conversation.orderedMessages.last, last.role == ChatMessage.Role.assistant.rawValue {
            store.remove(last, from: conversation)
            messages.removeLast()
        }
        startReply()
    }

    /// Your messages can be edited while nothing is generating.
    var canEdit: Bool { !isBusy }

    /// Replaces your message `id` with `text` and answers again from there,
    /// as editing a prompt does on Claude: every message after it is removed,
    /// and the model replies to the edited conversation.
    func edit(_ id: UUID, to text: String) {
        let edited = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !edited.isEmpty,
              let index = messages.firstIndex(where: { $0.id == id }),
              messages[index].role == .user
        else { return }
        let original = messages[index].text
        // A title made from the old first message follows the edit.
        if index == messages.firstIndex(where: { $0.role == .user }), conversation.title == Self.title(from: original) {
            conversation.title = Self.title(from: edited)
        }
        let removed = Set(messages[index...].map(\.id))
        for stored in conversation.orderedMessages where removed.contains(stored.id) {
            store.remove(stored, from: conversation)
        }
        messages.removeSubrange(index...)
        let user = store.append(.user, text: edited, to: conversation)
        messages.append(user.chatMessage)
        status = .idle
        startReply()
    }

    /// Stops the current reply; the partial text stays and is saved.
    func stop() {
        replyTask?.cancel()
    }

    /// Changes this chat's model; it loads with the next message.
    func selectModel(_ alias: String) {
        guard !isBusy, alias != conversation.modelAlias else { return }
        conversation.modelAlias = alias
        store.touch(conversation)
        backendLabel = nil
    }

    /// iOS forbids GPU work in the background and gives background CPU only
    /// ~30 s, so generation stops when the app leaves the foreground.
    func appDidLeaveForeground() {
        // Still getting the model ready: send the prompt again on return, so
        // it isn't lost (the download itself carries on in the background).
        if isBusy && !isGenerating { resendsOnReturn = true }
        stop()
    }

    /// Back in front: answer a prompt that leaving interrupted before the
    /// model was ready.
    func appDidBecomeActive() {
        guard resendsOnReturn else { return }
        resendsOnReturn = false
        Task {
            // Let the stopped turn finish unwinding first.
            while isBusy { try? await Task.sleep(for: .milliseconds(50)) }
            regenerate()
        }
    }

    // MARK: Turn handling

    /// Instructions the model gets before this chat's messages. They travel
    /// with each request, so changing them needs no reload.
    var systemPrompt: String {
        get { conversation.systemPrompt ?? "" }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            conversation.systemPrompt = trimmed.isEmpty ? nil : trimmed
            store.save()
        }
    }

    /// Roughly how full the context window is with this chat, its
    /// instructions and the message being typed. An estimate: the engine
    /// has no tokenizer to ask.
    var contextEstimate: (tokens: Int, window: Int?) {
        let text = ([systemPrompt] + messages.map(\.text) + [draft]).joined(separator: "\n")
        let window = modelDetails?.contextLength
            ?? model.map { TokenEstimate.window(for: $0, picked: services.contextWindows.tokens(for: $0.alias)) }
        return (TokenEstimate.tokens(in: text), window)
    }

    /// What the model is sent: the chat's instructions, then its messages.
    /// A chat longer than the model's context window keeps going: the
    /// oldest messages are left out of what's sent (they stay in the chat).
    private var historyForModel: (history: [ChatMessage], dropped: Int) {
        let instructions = systemPrompt
        let full = instructions.isEmpty ? messages : [ChatMessage(role: .system, text: instructions)] + messages
        guard let window = contextEstimate.window else { return (full, 0) }
        return TokenEstimate.fitting(full, window: window)
    }

    private func startReply() {
        let (history, dropped) = historyForModel
        droppedFromContext = dropped
        stoppedRepeating = false
        let modelAlias = conversation.modelAlias
        let reply = store.append(.assistant, text: "", to: conversation)
        messages.append(reply.chatMessage)
        currentReplyID = reply.id
        status = .loading(model: model?.displayName ?? modelAlias)
        replyTask = Task { [weak self] in
            await self?.runTurn(history: history, modelAlias: modelAlias, reply: reply)
        }
    }

    private func runTurn(history: [ChatMessage], modelAlias: String, reply: StoredMessage) async {
        let name = model?.displayName ?? modelAlias
        var meter = ReplyStatsMeter()
        var loadMs: Int?
        /// How far a download got, for "Download Interrupted at 412 MB of 1 GB".
        var lastProgress: DownloadProgress?
        // The Dynamic Island, shown only if the model has to download or load.
        var island: LiveActivityTracker?
        defer { liveTokensPerSecond = nil }
        do {
            // Plans memory (refusing a model that can't fit, instead of
            // letting iOS kill the app), downloads on first use, loads.
            let prepareStart = ContinuousClock.now
            var hadToLoad = false
            backendLabel = try await ModelPreparer(services: services, device: device).prepare(modelAlias) { [self] phase in
                hadToLoad = true
                if case .downloading(let progress) = phase { lastProgress = progress }
                // Downloads have the coordinator's Dynamic Island (it keeps
                // going if you leave the chat); loading gets the chat's.
                if case .loading = phase {
                    if island == nil {
                        island = LiveActivityTracker(service: services.liveActivities, title: "Chat")
                        island?.start(model: name)
                    }
                    island?.phase(phase)
                }
                guard currentReplyID == reply.id else { return }
                status = switch phase {
                case .downloading(let progress): .downloading(model: name, progress: progress)
                case .loading: .loading(model: name)
                }
            }
            island?.finish(detail: "Ready")
            if hadToLoad { loadMs = (ContinuousClock.now - prepareStart).milliseconds }
            try Task.checkCancellation()
            guard currentReplyID == reply.id else { return }
            status = .generating

            let requested = ContinuousClock.now
            var lastSave = requested
            var lastLiveUpdate = requested
            for try await token in try await services.chat.reply(to: history, model: modelAlias) {
                guard currentReplyID == reply.id else { return }
                let now = ContinuousClock.now
                meter.record(at: now - requested)
                append(token, to: reply)
                if now - lastLiveUpdate >= .milliseconds(500) {
                    liveTokensPerSecond = meter.tokensPerSecond
                    lastLiveUpdate = now
                }
                if now - lastSave >= saveInterval {
                    store.save()
                    lastSave = now
                }
            }
            attach(meter.stats(model: modelAlias, backend: backendLabel, loadMs: loadMs), to: reply)
            finishTurn(reply: reply, problem: nil)
        } catch ChatServiceError.stoppedRepeating {
            // Not a failure: the reply stays, with a line saying why it ended.
            if currentReplyID == reply.id { stoppedRepeating = true }
            attach(meter.stats(model: modelAlias, backend: backendLabel, loadMs: loadMs), to: reply)
            finishTurn(reply: reply, problem: nil)
        } catch {
            let problem = error is CancellationError ? nil : AppProblem.current(error, model: name, progress: lastProgress)
            if let problem {
                island?.fail(problem.title)
            } else {
                island?.finish(detail: "Stopped")
            }
            // A reply stopped or failed part-way keeps the stats of what arrived.
            attach(meter.stats(model: modelAlias, backend: backendLabel, loadMs: loadMs), to: reply)
            finishTurn(reply: reply, problem: problem)
        }
    }

    private func attach(_ stats: ReplyStats?, to reply: StoredMessage) {
        guard let stats, currentReplyID == reply.id else { return }
        reply.stats = stats
        if let index = messages.lastIndex(where: { $0.id == reply.id }) {
            messages[index].stats = stats
        }
    }

    // MARK: Model stats

    /// Averages over this chat's measured replies.
    var chatSummary: ChatStatsSummary {
        ChatStatsSummary(messages.compactMap(\.stats))
    }

    /// The most recent measured reply.
    var lastReplyStats: ReplyStats? {
        messages.last { $0.stats != nil }?.stats
    }

    /// The context window picked for this chat's model; nil is the default.
    var contextWindow: Int? {
        get { services.contextWindows.tokens(for: conversation.modelAlias) }
        set { setContextWindow(newValue) }
    }

    /// The temperature picked for this chat's model; nil is greedy (Precise).
    /// It's the model's setting, shared by every chat using it.
    var temperature: Double? {
        get { services.temperatures.temperature(for: conversation.modelAlias) }
        set { setSettings(temperature: newValue, contextWindow: contextWindow) }
    }

    /// Saves a new context window and, if the model is in memory, reloads
    /// it so the next reply uses it.
    func setContextWindow(_ tokens: Int?) {
        setSettings(temperature: temperature, contextWindow: tokens)
    }

    /// Top-p, top-k and repetition penalty picked for this chat's model.
    var sampling: SamplingSettings {
        services.sampling.settings(for: conversation.modelAlias)
    }

    /// Saves the model's temperature, context window and sampling (nil
    /// leaves sampling as it is); if any changed and the model is in
    /// memory, reloads it once so the next reply uses them.
    func setSettings(temperature: Double?, contextWindow tokens: Int?, sampling: SamplingSettings? = nil) {
        let alias = conversation.modelAlias
        let newSampling = (sampling ?? services.sampling.settings(for: alias)).normalized
        let changed = temperature != services.temperatures.temperature(for: alias)
            || tokens != services.contextWindows.tokens(for: alias)
            || newSampling != services.sampling.settings(for: alias)
        guard changed else { return }
        services.temperatures.set(temperature, for: alias)
        services.contextWindows.set(tokens, for: alias)
        services.sampling.set(newSampling, for: alias)
        guard modelDetails != nil else { return }
        Task {
            await services.chat.unload(model: alias)
            modelDetails = nil
            _ = try? await ModelPreparer(services: services, device: device).prepare(alias) { _ in }
            await refreshModelDetails()
        }
    }

    /// Reads engine details for the Model Stats sheet.
    func refreshModelDetails() async {
        device.refreshMemory()
        modelDetails = await services.chat.details(model: conversation.modelAlias)
        let catalog = services.catalog.chatModels()
        loadedModelNames = await services.chat.loadedModels().map { alias in
            catalog.first { $0.alias == alias }?.displayName ?? alias
        }
    }

    private func append(_ token: String, to reply: StoredMessage) {
        reply.text += token
        if let index = messages.lastIndex(where: { $0.id == reply.id }) {
            messages[index].text += token
        }
    }

    private func finishTurn(reply: StoredMessage, problem: AppProblem?) {
        guard currentReplyID == reply.id else { return }
        currentReplyID = nil
        // A reply stopped or failed before its first token leaves no bubble.
        if reply.text.isEmpty {
            messages.removeAll { $0.id == reply.id }
            store.remove(reply, from: conversation)
        } else {
            store.touch(conversation)
        }
        device.refreshMemory()
        if let problem {
            status = .failed(problem)
            alert = problem
        } else {
            status = .idle
        }
    }

    /// The first line of `prompt`, shortened to a chat title.
    static func title(from prompt: String) -> String {
        let firstLine = prompt.split(whereSeparator: \.isNewline).first.map(String.init) ?? prompt
        return firstLine.count > 40 ? String(firstLine.prefix(40)) + "…" : firstLine
    }
}
