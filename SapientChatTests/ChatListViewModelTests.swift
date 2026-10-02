import Foundation
import SwiftData
import Testing
@testable import SapientChat

@MainActor
struct ChatListViewModelTests {
    let container: ModelContainer
    let store: SwiftDataConversationStore
    let service = ControlledChatService()

    init() throws {
        container = try makeContainer()
        store = SwiftDataConversationStore(context: container.mainContext)
    }

    private func makeList() -> ChatListViewModel {
        ChatListViewModel(services: makeServices(chat: service), store: store)
    }

    @Test func newChatIsCreatedSavedAndOpened() throws {
        let list = makeList()
        list.newChat()
        #expect(list.conversations.count == 1)
        #expect(list.selectedID == list.conversations.first?.id)
        #expect(list.activeChat?.conversation.modelAlias == PhoneModel.defaultAlias)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Conversation>()) == 1)
    }

    @Test func aNewChatStartsWithTheLastUsedModel() {
        let list = makeList()
        list.newChat()
        list.activeChat?.selectModel(TestModels.big.alias)
        list.newChat()
        #expect(list.activeChat?.conversation.modelAlias == TestModels.big.alias)
    }

    @Test func chatsAndMessagesComeBackAfterRelaunch() async {
        let list = makeList()
        list.newChat()
        let chat = try! #require(list.activeChat)
        chat.draft = "Remember me"
        chat.send()
        #expect(await eventually { await service.replyCount == 1 })
        await service.send("I will", toReply: 0)
        await service.finishReply(0)
        #expect(await eventually { chat.status == .idle })

        // A new list on the same store is what the next app launch sees.
        let relaunched = makeList()
        #expect(relaunched.conversations.count == 1)
        relaunched.selectedID = relaunched.conversations.first?.id
        #expect(relaunched.activeChat?.messages.map(\.text) == ["Remember me", "I will"])
        #expect(relaunched.conversations.first?.title == "Remember me")
    }

    @Test func switchingChatsStopsTheReplyAndKeepsWhatArrived() async {
        let list = makeList()
        list.newChat()
        let first = try! #require(list.activeChat)
        first.draft = "Tell me a story"
        first.send()
        #expect(await eventually { await service.replyCount == 1 })
        await service.send("Once upon", toReply: 0)
        #expect(await eventually { first.messages.last?.text == "Once upon" })

        list.newChat()

        #expect(await eventually { first.status == .idle })
        #expect(first.conversation.orderedMessages.map(\.text) == ["Tell me a story", "Once upon"])
        #expect(list.activeChat?.conversation.id != first.conversation.id)
    }

    @Test func deletingTheOpenChatClosesIt() {
        let list = makeList()
        list.newChat()
        let conversation = list.conversations[0]
        list.delete(conversation)
        #expect(list.conversations.isEmpty)
        #expect(list.selectedID == nil)
        #expect(list.activeChat == nil)
    }

    @Test func renameTrimsAndFallsBackToUntitled() {
        let list = makeList()
        list.newChat()
        let conversation = list.conversations[0]
        list.rename(conversation, to: "  Trip plans  ")
        #expect(conversation.title == "Trip plans")
        list.rename(conversation, to: "   ")
        #expect(conversation.title == Conversation.untitled)
    }
}
