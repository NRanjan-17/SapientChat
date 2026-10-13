// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// The app's root: the chat list, the selected tab, and the long-lived
/// ViewModels behind each tab (shared device state, model manager,
/// benchmark, compare, API server).
@Observable
final class ChatListViewModel {
    private(set) var conversations: [Conversation] = []
    /// The open chat. Setting it opens that conversation.
    var selectedID: Conversation.ID? {
        didSet { if selectedID != oldValue { openSelected() } }
    }
    private(set) var activeChat: ChatViewModel?
    /// The visible tab. Starting a chat from the Models tab switches to Chats.
    var selectedTab: AppTab = .chats
    let device: DeviceStatus
    /// The local API server; lives as long as the app so it keeps serving
    /// with its screen closed.
    let server: ServerViewModel
    /// API requests other apps on this device hand over by URL.
    let handoff: HandoffViewModel
    /// The Playground tab: API requests composed and run in the app.
    let playground: PlaygroundViewModel
    /// The model manager, kept for the app's lifetime so downloads and
    /// loads carry on (and still show progress) after its screen closes.
    let models: ModelManagerViewModel
    /// Shown once at launch when iOS ended the app while it loaded a model.
    var launchProblem: AppProblem?
    /// The model `launchProblem` is about, for Try Again.
    @ObservationIgnored private var launchProblemModel: String?
    /// The Benchmark tab's two modes; kept so results survive tab switches.
    let benchmark: BenchmarkViewModel
    let compare: CompareViewModel
    /// Every finished benchmark, kept across launches.
    let benchmarkHistory: BenchmarkHistory
    /// Saved prompt sets and their runs (the Benchmark tab's third mode).
    let promptSets: PromptSetsViewModel

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let store: any ConversationStore

    init(
        services: AppServices, store: any ConversationStore,
        liveActivities: any LiveActivityService = NoLiveActivities(),
        requestLog: any RequestLogStore = InMemoryRequestLogStore(),
        benchmarkHistory: any BenchmarkHistoryStore = InMemoryBenchmarkHistoryStore(),
        promptSets: any PromptSetStore = InMemoryPromptSetStore()
    ) {
        self.services = services
        self.store = store
        device = DeviceStatus(memoryService: services.memory, thermalService: services.thermal)
        let router = ServeRouter(services: services, device: device)
        router.liveActivities = liveActivities
        if let island = liveActivities as? WindowIsland {
            router.activity = { island.snapshot }
        }
        server = ServerViewModel(router: router, liveActivities: liveActivities, requestLog: requestLog)
        handoff = HandoffViewModel(router: router)
        playground = PlaygroundViewModel(
            router: router,
            model: store.conversations().first?.modelAlias ?? PhoneModel.defaultAlias,
            // The address another device would use, else this one's.
            baseURL: { [server] in server.endpoints.last?.url ?? "http://127.0.0.1:\(ServerViewModel.defaultPort)" }
        )
        models = ModelManagerViewModel(services: services, device: device)
        router.onModelPhase = { [models] alias, phase in models.apiPhase(phase, for: alias) }
        router.onSettingsChanged = { [models] in Task { await models.refresh() } }
        services.downloadCoordinator.onChange = { [models] alias, progress in models.downloadChanged(progress, for: alias) }
        let catalog = services.catalog.chatModels()
        let firstModel = store.conversations().first?.modelAlias ?? PhoneModel.defaultAlias
        benchmark = BenchmarkViewModel(
            model: firstModel,
            service: services.benchmark,
            availableModels: catalog,
            liveActivities: liveActivities
        ) { [device] _ in device.refreshMemory() }
        compare = CompareViewModel(services: services, device: device, initialModel: firstModel, liveActivities: liveActivities)
        self.promptSets = PromptSetsViewModel(services: services, device: device, store: promptSets, initialModel: firstModel)
        let history = BenchmarkHistory(store: benchmarkHistory)
        self.benchmarkHistory = history
        benchmark.onResult = { history.record($0) }
        refresh()
        if let alias = services.memoryLedger.takeLoadThatEndedTheApp() {
            let name = catalog.first { $0.alias == alias }?.displayName ?? alias
            launchProblem = .closedWhileLoading(model: name)
            launchProblemModel = alias
        }
        models.beforeUnloadAll = { [weak self] in
            self?.activeChat?.stop()
            self?.benchmark.cancel()
            self?.compare.cancel()
            self?.promptSets.cancel()
        }
        models.onNewChat = { [weak self] alias in
            self?.newChat(model: alias)
            self?.selectedTab = .chats
        }
    }

    /// The model a new chat starts with: the last one used, else the default.
    var modelForNewChat: String {
        conversations.first?.modelAlias ?? PhoneModel.defaultAlias
    }

    func refresh() {
        conversations = store.conversations()
    }

    func newChat() {
        newChat(model: modelForNewChat)
    }

    /// A new chat using `model` (e.g. one just loaded in the model manager).
    /// A chat that never got a message is reused, so tapping New Chat
    /// twice doesn't leave empty chats in the list.
    func newChat(model: String) {
        if let empty = conversations.first(where: \.messages.isEmpty) {
            if empty.modelAlias != model {
                empty.modelAlias = model
            }
            store.touch(empty)
            refresh()
            selectedID = empty.id
            return
        }
        let conversation = store.createConversation(model: model)
        refresh()
        selectedID = conversation.id
    }

    func rename(_ conversation: Conversation, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        conversation.title = trimmed.isEmpty ? Conversation.untitled : trimmed
        store.save()
        refresh()
    }

    func delete(_ conversation: Conversation) {
        if conversation.id == selectedID {
            selectedID = nil
        }
        store.delete(conversation)
        refresh()
    }

    /// Opens a logged request in the Playground, ready to change and send again.
    func openInPlayground(_ entry: RequestLogEntry) {
        playground.open(method: entry.method, path: entry.path, body: entry.requestBody)
        selectedTab = .playground
    }

    /// The context window `alias` loads with, for token estimates.
    func contextWindow(for alias: String) -> Int? {
        services.catalog.chatModels().first { $0.alias == alias }.map {
            TokenEstimate.window(for: $0, picked: services.contextWindows.tokens(for: alias))
        }
    }

    /// The model picker for Benchmark and Compare.
    func makeModelSelector(selected: String, onSelect: @escaping (String) -> Void) -> ModelSelectorViewModel {
        ModelSelectorViewModel(selected: selected, services: services, device: device, onSelect: onSelect)
    }

    func makeModelSelector(for chat: ChatViewModel) -> ModelSelectorViewModel {
        ModelSelectorViewModel(selected: chat.conversation.modelAlias, services: services, device: device) { [weak chat] alias in
            chat?.selectModel(alias)
        }
    }


    /// Back in front: resume any download iOS cut off.
    func appDidBecomeActive() {
        services.downloadCoordinator.appBecameActive()
        activeChat?.appDidBecomeActive()
    }

    /// iOS forbids GPU work in the background: stop whatever is generating
    /// (a chat reply, a benchmark, a comparison) when the app leaves.
    /// Loads the model iOS ended the app over, now planned at its real size
    /// (idle models released first, or a clear "won't fit").
    func retryLaunchProblem() {
        guard let alias = launchProblemModel else { return }
        launchProblemModel = nil
        selectedTab = .models
        models.load(alias: alias)
    }

    func appDidLeaveForeground() {
        // Downloads keep going in the background; replies and benchmarks stop.
        services.downloadCoordinator.appMovedToBackground()
        activeChat?.appDidLeaveForeground()
        benchmark.cancel()
        compare.cancel()
        promptSets.cancel()
    }

    private func openSelected() {
        // Leaving a chat mid-reply stops it; the partial reply is saved.
        activeChat?.stop()
        activeChat = conversations.first { $0.id == selectedID }.map {
            ChatViewModel(conversation: $0, services: services, store: store, device: device)
        }
        refresh()
    }
}
