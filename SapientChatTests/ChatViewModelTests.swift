import Foundation
import SwiftData
import Testing
@testable import SapientChat

@MainActor
struct ChatViewModelTests {
    let container: ModelContainer
    let store: SwiftDataConversationStore
    let service = ControlledChatService()

    init() throws {
        container = try makeContainer()
        store = SwiftDataConversationStore(context: container.mainContext)
    }

    private func makeChat(
        model: PhoneModel = TestModels.small,
        memory: FixedMemory = FixedMemory(),
        saveInterval: Duration = .seconds(60)
    ) -> ChatViewModel {
        let services = makeServices(chat: service, memory: memory)
        let conversation = store.createConversation(model: model.alias)
        let device = DeviceStatus(memoryService: memory, thermalService: SilentThermalService())
        return ChatViewModel(conversation: conversation, services: services, store: store, device: device, saveInterval: saveInterval)
    }

    private func send(_ text: String, in chat: ChatViewModel) {
        chat.draft = text
        chat.send()
    }

    /// What a fresh context on the same container sees: only saved data.
    private func savedTexts() throws -> [String] {
        let fresh = ModelContext(container)
        let chats = try fresh.fetch(FetchDescriptor<Conversation>())
        return chats.first?.orderedMessages.map(\.text) ?? []
    }

    @Test func streamsTheReplyAndSavesTheTurn() async throws {
        let chat = makeChat()
        send("Hi there", in: chat)
        #expect(await eventually { await service.replyCount == 1 })

        await service.send("Hel", toReply: 0)
        await service.send("lo", toReply: 0)
        await service.finishReply(0)

        #expect(await eventually { chat.status == .idle })
        #expect(chat.messages.map(\.text) == ["Hi there", "Hello"])
        #expect(try savedTexts() == ["Hi there", "Hello"])
        #expect(chat.conversation.title == "Hi there", "the first message names the chat")
        #expect(chat.backendLabel == "test-backend")
    }

    @Test func everyTurnSendsTheWholeHistory() async {
        let chat = makeChat()
        send("First", in: chat)
        #expect(await eventually { await service.replyCount == 1 })
        await service.send("One", toReply: 0)
        await service.finishReply(0)
        #expect(await eventually { chat.status == .idle })

        send("Second", in: chat)
        #expect(await eventually { await service.replyCount == 2 })
        let histories = await service.histories
        #expect(histories[1].map(\.text) == ["First", "One", "Second"])
        #expect(histories[1].map(\.role) == [.user, .assistant, .user])
        // The model is loaded once and reused.
        #expect(await service.loadedModels == [TestModels.small.alias])
    }

    @Test func aStreamingReplyIsSavedWhileItArrives() async throws {
        let chat = makeChat(saveInterval: .zero)
        send("Hi", in: chat)
        #expect(await eventually { await service.replyCount == 1 })
        await service.send("Partial", toReply: 0)

        // Not finished yet, but already on disk: a crash now keeps it.
        #expect(await eventually { (try? savedTexts()) == ["Hi", "Partial"] })
    }

    @Test func stopBeforeTheFirstTokenLeavesNoEmptyReply() async throws {
        let chat = makeChat()
        send("Hi", in: chat)
        #expect(await eventually { chat.status == .generating })

        chat.stop()

        #expect(await eventually { chat.status == .idle })
        #expect(chat.messages.map(\.text) == ["Hi"])
        #expect(try savedTexts() == ["Hi"])
    }

    @Test func refusesAModelThatCannotFitAndKeepsTheMessageForRetry() async throws {
        let chat = makeChat(model: TestModels.big, memory: tightMemory)
        send("Hi", in: chat)

        #expect(await eventually {
            if case .failed(let message) = chat.status { message.contains("smollm2-1.7b") } else { false }
        })
        #expect(chat.messages.map(\.text) == ["Hi"])
        #expect(await service.loadedModels.isEmpty, "nothing was loaded")
        #expect(chat.canRegenerate, "the user can retry, e.g. after picking a smaller model")
    }

    @Test func regenerateReplacesTheLastReply() async throws {
        let chat = makeChat()
        send("Hi", in: chat)
        #expect(await eventually { await service.replyCount == 1 })
        await service.send("Old", toReply: 0)
        await service.finishReply(0)
        #expect(await eventually { chat.status == .idle })

        chat.regenerate()
        #expect(await eventually { await service.replyCount == 2 })
        await service.send("New", toReply: 1)
        await service.finishReply(1)

        #expect(await eventually { chat.status == .idle })
        #expect(chat.messages.map(\.text) == ["Hi", "New"])
        #expect(try savedTexts() == ["Hi", "New"])
        #expect(await service.histories[1].map(\.text) == ["Hi"], "the old reply is not sent back")
    }

    @Test func selectingAModelIsSavedOnTheChat() {
        let chat = makeChat()
        chat.selectModel(TestModels.big.alias)
        #expect(chat.conversation.modelAlias == TestModels.big.alias)
        #expect(chat.modelName == "smollm2-1.7b")
    }

    @Test func titlesComeFromTheFirstLineAndAreShortened() {
        #expect(ChatViewModel.title(from: "Hello\nsecond line") == "Hello")
        let long = String(repeating: "a", count: 60)
        #expect(ChatViewModel.title(from: long) == String(repeating: "a", count: 40) + "…")
    }
}

@MainActor
struct MemoryFitTests {
    @Test func estimatesFollowTheStorageFormat() {
        let q4 = PhoneModel(alias: "a", repoId: "a", params: "1.7B Q4_K_M", billions: 1.7)
        let full = PhoneModel(alias: "b", repoId: "b", params: "1.7B", billions: 1.7)
        // 1.7e9 × bytes per parameter + 0.6 GB; compared loosely (floating point).
        #expect(q4.estimatedMemoryBytes.distance(to: 1_620_000_000).magnitude < 1_000)
        #expect(full.estimatedMemoryBytes.distance(to: 2_810_000_000).magnitude < 1_000)
    }

    @Test func memoryFreedByTheCurrentModelCounts() {
        let full = TestModels.big
        #expect(full.fitProblem(availableBytes: 2_000_000_000) != nil)
        #expect(full.fitProblem(availableBytes: 2_000_000_000, reclaimableBytes: 900_000_000) == nil)
        #expect(full.fitProblem(availableBytes: nil) == nil, "no known limit, e.g. the simulator")
    }
}

struct PhoneModelTests {
    @Test(arguments: [
        ("135M Q4_K_M", 0.135),
        ("1.5B", 1.5),
        ("0.5B Q4_K_M", 0.5),
    ])
    func parsesCatalogSizes(params: String, billions: Double) {
        #expect(PhoneModel.billions(fromParams: params) == billions)
    }

    @Test(arguments: ["47B-A13B Q4_K_M", "106B-A12B", ""])
    func rejectsSizesItCannotParse(params: String) {
        #expect(PhoneModel.billions(fromParams: params) == nil)
    }

    @Test func displayNameAndFormat() {
        #expect(TestModels.small.displayName == "smollm2-135m-q4")
        #expect(TestModels.small.format == "4-bit")
        #expect(TestModels.big.format == "Full precision")
    }
}
