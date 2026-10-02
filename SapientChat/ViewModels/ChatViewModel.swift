import Foundation
import Observation

/// State and actions for the chat screen. Main-actor isolated (the target
/// default). Talks to the engine only through the injected services.
@Observable
final class ChatViewModel {
    private(set) var messages: [ChatMessage] = []
    private(set) var status: ChatStatus = .idle
    private(set) var backendLabel: String?
    private(set) var thermalPressure: ThermalPressure = .nominal
    private(set) var memory = MemoryStatus.unknown
    let availableModels: [PhoneModel]
    var selectedModel = PhoneModel.defaultAlias
    var draft = ""

    @ObservationIgnored private let chatService: any ChatService
    @ObservationIgnored private let benchmarkService: any BenchmarkService
    @ObservationIgnored private let thermalService: any ThermalService
    @ObservationIgnored private let memoryService: any MemoryService
    @ObservationIgnored private var loadedModel: String?
    /// The reply being produced; Stop and Clear cancel it.
    @ObservationIgnored private var replyTask: Task<Void, Never>?
    /// The reply bubble of the current turn. A turn whose bubble is no
    /// longer current (after Clear) never writes to the UI again.
    @ObservationIgnored private var currentReplyID: UUID?
    /// Tail of a serial chain: turns and resets run one after another, so a
    /// Clear's history reset never races a reply that is still finishing.
    @ObservationIgnored private var lastOperation: Task<Void, Never>?

    init(
        chatService: any ChatService,
        benchmarkService: any BenchmarkService,
        catalog: any ModelCatalogService,
        thermalService: any ThermalService,
        memoryService: any MemoryService,
        messages: [ChatMessage] = []
    ) {
        self.messages = messages
        self.chatService = chatService
        self.benchmarkService = benchmarkService
        self.thermalService = thermalService
        self.memoryService = memoryService
        availableModels = catalog.chatModels()
        memory = memoryService.status()
    }

    /// The app's real wiring: chat and benchmark share ONE engine, so only
    /// one model is ever in memory.
    static func live() -> ChatViewModel {
        let engine = SapientChatService()
        return ChatViewModel(
            chatService: engine,
            benchmarkService: engine,
            catalog: SapientModelCatalog(),
            thermalService: SapientThermalService(),
            memoryService: SapientMemoryService()
        )
    }

    var isBusy: Bool {
        switch status {
        case .idle, .failed: false
        case .loading, .generating: true
        }
    }

    var isGenerating: Bool { status == .generating }

    var canSend: Bool {
        !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var canClear: Bool { !isBusy && !messages.isEmpty }

    var statusText: String {
        let thermal = thermalPressure.label.map { " · \($0)" } ?? ""
        let used = memory.footprintBytes.map { " · \(Self.format(bytes: $0)) used" } ?? ""
        return switch status {
        case .idle: "On-device" + (backendLabel.map { " · \($0)" } ?? "") + used + thermal
        case .loading(let model): "Loading \(model). The first run downloads it…"
        case .generating: "Generating…" + thermal
        case .failed(let message): "Error: \(message)"
        }
    }

    // MARK: Actions

    func send() {
        let prompt = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }
        let model = selectedModel
        let needsLoad = loadedModel != model
        // Refuse a model that can't fit instead of letting iOS kill the app.
        if needsLoad, let problem = memoryProblem(loading: model) {
            status = .failed(problem)
            return
        }
        draft = ""

        messages.append(ChatMessage(role: .user, text: prompt))
        let reply = ChatMessage(role: .assistant, text: "")
        messages.append(reply)
        currentReplyID = reply.id
        status = needsLoad ? .loading(model: model) : .generating

        replyTask = enqueue { [weak self] in
            await self?.runTurn(prompt: prompt, replyID: reply.id, model: model, needsLoad: needsLoad)
        }
    }

    /// The benchmark screen for the selected model, on the shared engine.
    func makeBenchmarkViewModel() -> BenchmarkViewModel {
        let model = selectedModel
        return BenchmarkViewModel(model: model, service: benchmarkService) { [weak self] succeeded in
            // A successful benchmark leaves `model` loaded; after a failure
            // nothing is known, so the next message reloads (a no-op in the
            // service if the model is in fact still loaded).
            self?.loadedModel = succeeded ? model : nil
            self?.refreshMemory()
        }
    }

    /// Why `alias` can't be loaded right now, or nil if it should fit. The
    /// current model is released first, so its footprint counts as free.
    func memoryProblem(loading alias: String) -> String? {
        guard let model = availableModels.first(where: { $0.alias == alias }) else { return nil }
        memory = memoryService.status()
        let reclaimable = loadedModel == nil ? 0 : memory.footprintBytes ?? 0
        return model.fitProblem(availableBytes: memory.availableBytes, reclaimableBytes: reclaimable)
    }

    func refreshMemory() {
        memory = memoryService.status()
    }

    static func format(bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .memory))
    }

    /// Stops the current reply; the partial text stays.
    func stop() {
        replyTask?.cancel()
    }

    func clearConversation() {
        replyTask?.cancel()
        replyTask = nil
        currentReplyID = nil
        messages.removeAll()
        status = .idle
        let chatService = chatService
        enqueue { await chatService.reset() }
    }

    /// iOS forbids GPU work in the background and gives background CPU only
    /// ~30 s, so generation stops when the app leaves the foreground.
    func appDidLeaveForeground() {
        stop()
    }

    /// Test hook: launching with `-autosend "<prompt>"` sends one message.
    func handleLaunchArguments(_ arguments: [String]) {
        guard let flag = arguments.firstIndex(of: "-autosend"), arguments.indices.contains(flag + 1) else { return }
        draft = arguments[flag + 1]
        send()
    }

    /// Mirrors the device's thermal state until the calling task is cancelled.
    func observeThermalPressure() async {
        for await pressure in thermalService.pressureUpdates() {
            thermalPressure = pressure
        }
    }

    // MARK: Turn handling

    @discardableResult
    private func enqueue(_ operation: @escaping () async -> Void) -> Task<Void, Never> {
        let previous = lastOperation
        let task = Task {
            await previous?.value
            await operation()
        }
        lastOperation = task
        return task
    }

    private func runTurn(prompt: String, replyID: UUID, model: String, needsLoad: Bool) async {
        do {
            if needsLoad {
                backendLabel = try await chatService.load(model: model)
                loadedModel = model
                refreshMemory()
            }
            try Task.checkCancellation()
            guard currentReplyID == replyID else { return }
            status = .generating

            for try await token in try await chatService.reply(to: prompt) {
                guard currentReplyID == replyID else { return }
                append(token, to: replyID)
            }
            finishTurn(replyID: replyID, error: nil)
        } catch {
            finishTurn(replyID: replyID, error: error)
        }
    }

    private func append(_ token: String, to replyID: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == replyID }) else { return }
        messages[index].text += token
    }

    private func finishTurn(replyID: UUID, error: (any Error)?) {
        guard currentReplyID == replyID else { return }
        refreshMemory()
        // A reply stopped or failed before its first token leaves no bubble.
        if let index = messages.firstIndex(where: { $0.id == replyID }), messages[index].text.isEmpty {
            messages.remove(at: index)
        }
        if let error, !(error is CancellationError) {
            // SapientError isn't a LocalizedError; its description carries the reason.
            status = .failed(String(describing: error))
        } else {
            status = .idle
        }
    }
}
