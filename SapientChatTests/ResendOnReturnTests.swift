import Foundation
import SwiftData
import Testing
@testable import SapientChat

@MainActor
struct ResendOnReturnTests {
    @Test func leavingWhileTheModelGetsReadyResendsThePromptOnReturn() async throws {
        let container = try makeContainer()
        let store = SwiftDataConversationStore(context: container.mainContext)
        let storage = FakeStorage()
        let services = makeServices(
            chat: ControlledChatService(autoReply: ["Hello", "!"]),
            storage: storage,
            downloads: FakeDownloader(storage: storage, steps: 30)
        )
        let chat = ChatViewModel(
            conversation: store.createConversation(model: TestModels.small.alias),
            services: services, store: store,
            device: DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        )
        chat.draft = "Hi"
        chat.send()
        #expect(await eventually { if case .downloading = chat.status { true } else { false } })

        chat.appDidLeaveForeground() // the reply stops; the download carries on
        chat.appDidBecomeActive()

        #expect(await eventually { chat.messages.last?.text == "Hello!" }, "answered without sending again")
        #expect(chat.messages.filter { $0.role == .user }.count == 1)
        #expect(chat.messages.count == 2, "the stopped empty reply was replaced, not kept")
    }

    @Test func leavingMidReplyDoesNotResend() async throws {
        let container = try makeContainer()
        let store = SwiftDataConversationStore(context: container.mainContext)
        let service = ControlledChatService()
        let chat = ChatViewModel(
            conversation: store.createConversation(model: TestModels.small.alias),
            services: makeServices(chat: service), store: store,
            device: DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        )
        chat.draft = "Hi"
        chat.send()
        #expect(await eventually { chat.isGenerating })
        chat.appDidLeaveForeground()
        chat.appDidBecomeActive()
        #expect(await eventually { !chat.isBusy })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(await service.replyCount == 1, "no second reply started")
    }
}
