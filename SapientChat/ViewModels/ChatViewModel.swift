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
    var draft = ""

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let store: any ConversationStore
    /// Shared app-wide state (memory, thermal) owned by the chat list.
    @ObservationIgnored private let device: DeviceStatus
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
            [modelName, backendLabel, device.memory.footprintBytes.map { "\(Format.bytes($0)) used" }]
                .compactMap { $0 }.joined(separator: " · ") + thermal
        case .downloading(let model, let progress): "Downloading \(model) · \(progress.text)"
        case .loading(let model): "Loading \(model) into memory…"
        case .generating: "Generating…" + thermal
        case .failed(let message): "Error: \(message)"
        }
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

    /// The benchmark screen for this chat's model, on the shared engine.
    func makeBenchmarkViewModel() -> BenchmarkViewModel {
        BenchmarkViewModel(model: conversation.modelAlias, service: services.benchmark) { [device] _ in
            device.refreshMemory()
        }
    }

    /// iOS forbids GPU work in the background and gives background CPU only
    /// ~30 s, so generation stops when the app leaves the foreground.
    func appDidLeaveForeground() {
        stop()
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
        do {
            // Plans memory (refusing a model that can't fit, instead of
            // letting iOS kill the app), downloads on first use, loads.
            backendLabel = try await ModelPreparer(services: services, device: device).prepare(modelAlias) { phase in
                guard currentReplyID == reply.id else { return }
                status = switch phase {
                case .downloading(let progress): .downloading(model: name, progress: progress)
                case .loading: .loading(model: name)
                }
            }
            try Task.checkCancellation()
            guard currentReplyID == reply.id else { return }
            status = .generating

            var lastSave = ContinuousClock.now
            for try await token in try await services.chat.reply(to: history, model: modelAlias) {
                guard currentReplyID == reply.id else { return }
                append(token, to: reply)
                if ContinuousClock.now - lastSave >= saveInterval {
                    store.save()
                    lastSave = .now
                }
            }
            finishTurn(reply: reply, error: nil)
        } catch {
            finishTurn(reply: reply, error: error)
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
