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
    private(set) var backendLabel: String?
    /// Speed of the reply streaming right now (≈ tok/s), updated twice a second.
    private(set) var liveTokensPerSecond: Double?
    /// Engine details of this chat's model, for the Model Stats sheet.
    private(set) var modelDetails: LoadedModelDetails?
    /// Display names of the models in memory, most recently used first.
    private(set) var loadedModelNames: [String] = []
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
        case .failed(let message): "Error: \(message)"
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

    private func startReply() {
        let history = messages
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
            finishTurn(reply: reply, error: nil)
        } catch {
            if error is CancellationError {
                island?.finish(detail: "Stopped")
            } else {
                island?.fail(String(describing: error))
            }
            // A reply stopped or failed part-way keeps the stats of what arrived.
            attach(meter.stats(model: modelAlias, backend: backendLabel, loadMs: loadMs), to: reply)
            finishTurn(reply: reply, error: error)
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

    /// Saves a new context window and, if the model is in memory, reloads
    /// it so the next reply uses it.
    func setContextWindow(_ tokens: Int?) {
        let alias = conversation.modelAlias
        guard tokens != services.contextWindows.tokens(for: alias) else { return }
        services.contextWindows.set(tokens, for: alias)
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

    private func finishTurn(reply: StoredMessage, error: (any Error)?) {
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
        if let error, !(error is CancellationError) {
            if case ChatViewModelError.wontFit(let message) = error {
                status = .failed(message)
            } else {
                // SapientError isn't a LocalizedError; its description carries the reason.
                status = .failed(String(describing: error))
            }
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
