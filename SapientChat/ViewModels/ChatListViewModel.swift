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
    /// The model manager, kept for the app's lifetime so downloads and
    /// loads carry on (and still show progress) after its screen closes.
    let models: ModelManagerViewModel
    /// The Benchmark tab's two modes; kept so results survive tab switches.
    let benchmark: BenchmarkViewModel
    let compare: CompareViewModel

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let store: any ConversationStore

    init(
        services: AppServices, store: any ConversationStore,
        liveActivities: any LiveActivityService = NoLiveActivities(),
        requestLog: any RequestLogStore = InMemoryRequestLogStore()
    ) {
        self.services = services
        self.store = store
        device = DeviceStatus(memoryService: services.memory, thermalService: services.thermal)
        let router = ServeRouter(services: services, device: device)
        router.liveActivities = liveActivities
        server = ServerViewModel(router: router, liveActivities: liveActivities, requestLog: requestLog)
        handoff = HandoffViewModel(router: router)
        models = ModelManagerViewModel(services: services, device: device)
        router.onModelPhase = { [models] alias, phase in models.apiPhase(phase, for: alias) }
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
        refresh()
        models.beforeUnloadAll = { [weak self] in
            self?.activeChat?.stop()
            self?.benchmark.cancel()
            self?.compare.cancel()
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
    func newChat(model: String) {
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
    func appDidLeaveForeground() {
        // Downloads keep going in the background; replies and benchmarks stop.
        services.downloadCoordinator.appMovedToBackground()
        activeChat?.appDidLeaveForeground()
        benchmark.cancel()
        compare.cancel()
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
