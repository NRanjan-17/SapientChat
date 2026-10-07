import Foundation
import Observation

/// The chat list and the app's entry point to every screen. Owns the
/// shared device state and the ViewModel of the open chat.
@Observable
final class ChatListViewModel {
    private(set) var conversations: [Conversation] = []
    /// The open chat. Setting it opens that conversation.
    var selectedID: Conversation.ID? {
        didSet { if selectedID != oldValue { openSelected() } }
    }
    private(set) var activeChat: ChatViewModel?
    let device: DeviceStatus
    /// The local API server; lives as long as the app so it keeps serving
    /// with its screen closed.
    let server: ServerViewModel
    /// API requests other apps on this device hand over by URL.
    let handoff: HandoffViewModel

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let store: any ConversationStore

    init(services: AppServices, store: any ConversationStore) {
        self.services = services
        self.store = store
        device = DeviceStatus(memoryService: services.memory, thermalService: services.thermal)
        let router = ServeRouter(services: services, device: device)
        server = ServerViewModel(router: router)
        handoff = HandoffViewModel(router: router)
        refresh()
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

    func makeModelSelector(for chat: ChatViewModel) -> ModelSelectorViewModel {
        ModelSelectorViewModel(selected: chat.conversation.modelAlias, services: services, device: device) { [weak chat] alias in
            chat?.selectModel(alias)
        }
    }

    func makeCompareViewModel() -> CompareViewModel {
        CompareViewModel(services: services, device: device, initialModel: activeChat?.conversation.modelAlias ?? modelForNewChat)
    }

    /// `onNewChat` runs after the manager has loaded the model.
    func makeModelManager(onNewChat: @escaping (String) -> Void) -> ModelManagerViewModel {
        ModelManagerViewModel(services: services, device: device) { [weak self] alias in
            self?.newChat(model: alias)
            onNewChat(alias)
        }
    }

    func appDidLeaveForeground() {
        activeChat?.appDidLeaveForeground()
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
