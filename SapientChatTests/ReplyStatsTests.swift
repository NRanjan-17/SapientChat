import Foundation
import SwiftData
import Testing
@testable import SapientChat

struct ReplyStatsMeterTests {
    @Test func speedExcludesTheFirstPiece() throws {
        var meter = ReplyStatsMeter()
        // First piece after 300 ms (prefill), then one every 50 ms.
        for ms in [300, 350, 400, 450, 500] { meter.record(at: .milliseconds(ms)) }

        let stats = try #require(meter.stats(model: "m", backend: "cpu", loadMs: 1_200))
        #expect(stats.firstTokenMs == 300)
        #expect(stats.pieces == 5)
        #expect(stats.durationMs == 500)
        #expect(stats.loadMs == 1_200)
        // 4 pieces over 200 ms = 20 per second.
        #expect(abs((stats.tokensPerSecond ?? 0) - 20) < 1e-9)
    }

    @Test func oneOrNoPiecesHaveNoSpeed() {
        var meter = ReplyStatsMeter()
        #expect(meter.stats(model: "m", backend: nil, loadMs: nil) == nil)
        meter.record(at: .milliseconds(80))
        #expect(meter.tokensPerSecond == nil)
        #expect(meter.stats(model: "m", backend: nil, loadMs: nil)?.pieces == 1)
    }

    @Test func summaryReadsNaturally() {
        let stats = ReplyStats(firstTokenMs: 312, tokensPerSecond: 27.44, pieces: 128, durationMs: 4_800,
                               loadMs: nil, model: "m", backend: nil)
        #expect(stats.summary.hasPrefix("27.4 tok/s · 312 ms first token · 128 tokens · "))
    }

    @Test func chatSummaryAveragesOnlyMeasuredSpeeds() {
        let make = { (speed: Double?, firstToken: Int) in
            ReplyStats(firstTokenMs: firstToken, tokensPerSecond: speed, pieces: 2, durationMs: 1, loadMs: nil, model: "m", backend: nil)
        }
        let summary = ChatStatsSummary([make(20, 100), make(30, 300), make(nil, 200)])
        #expect(summary.replies == 3)
        #expect(summary.averageTokensPerSecond == 25)
        #expect(summary.bestTokensPerSecond == 30)
        #expect(summary.averageFirstTokenMs == 200)
        #expect(ChatStatsSummary([]).averageTokensPerSecond == nil)
    }
}

@MainActor
struct ChatReplyStatsTests {
    @Test func aReplyIsMeasuredAndItsStatsAreSaved() async throws {
        let container = try makeContainer()
        let store = SwiftDataConversationStore(context: container.mainContext)
        let service = ControlledChatService()
        let services = makeServices(chat: service)
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let chat = ChatViewModel(
            conversation: store.createConversation(model: TestModels.small.alias),
            services: services, store: store, device: device
        )

        chat.draft = "Hi"
        chat.send()
        #expect(await eventually { await service.replyCount == 1 })
        for piece in ["Hel", "lo", " there"] {
            await service.send(piece, toReply: 0)
            try await Task.sleep(for: .milliseconds(20))
        }
        await service.finishReply(0)
        #expect(await eventually { chat.status == .idle })

        let stats = try #require(chat.messages.last?.stats)
        #expect(stats.pieces == 3)
        #expect(stats.model == TestModels.small.alias)
        #expect(stats.backend == "test-backend")
        #expect(stats.loadMs != nil, "the first reply loaded the model")
        #expect(stats.tokensPerSecond != nil)
        #expect(chat.liveTokensPerSecond == nil, "live speed clears when the reply ends")
        #expect(chat.chatSummary.replies == 1)

        // A fresh context sees only what was saved: the stats survive relaunch.
        let saved = try ModelContext(container).fetch(FetchDescriptor<StoredMessage>())
        #expect(saved.first { $0.role == "assistant" }?.stats == stats)
    }

    @Test func detailsComeFromTheLoadedModel() async throws {
        let container = try makeContainer()
        let store = SwiftDataConversationStore(context: container.mainContext)
        let service = ControlledChatService()
        _ = try await service.load(model: TestModels.small.alias)
        let chat = ChatViewModel(
            conversation: store.createConversation(model: TestModels.small.alias),
            services: makeServices(chat: service), store: store,
            device: DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        )

        await chat.refreshModelDetails()

        #expect(chat.modelDetails?.contextLength == 8192)
        #expect(chat.loadedModelNames == [TestModels.small.displayName])
    }
}
