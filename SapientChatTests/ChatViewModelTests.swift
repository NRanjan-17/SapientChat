import Foundation
import Testing
@testable import SapientChat

/// A `ChatService` the test drives by hand: each reply's tokens are pushed
/// explicitly, so the test controls exactly when they arrive.
actor ControlledChatService: ChatService {
    private(set) var loadedModels: [String] = []
    private(set) var resetCount = 0
    private var replies: [AsyncThrowingStream<String, any Error>.Continuation] = []

    var replyCount: Int { replies.count }

    func load(model: String) async throws -> String {
        loadedModels.append(model)
        return "test-backend"
    }

    func reply(to prompt: String) async throws -> AsyncThrowingStream<String, any Error> {
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        replies.append(continuation)
        return stream
    }

    func reset() async {
        resetCount += 1
    }

    func send(_ token: String, toReply index: Int) {
        replies[index].yield(token)
    }

    func finishReply(_ index: Int) {
        replies[index].finish()
    }
}

struct FixedCatalog: ModelCatalogService {
    static let big = PhoneModel(alias: "smollm2-1.7b", params: "1.7B", billions: 1.7)

    func chatModels() -> [PhoneModel] {
        [PhoneModel(alias: PhoneModel.defaultAlias, params: "135M Q4_K_M", billions: 0.135), Self.big]
    }
}

struct FixedMemory: MemoryService {
    var memory = MemoryStatus(footprintBytes: 200_000_000, availableBytes: 3_000_000_000)

    func status() -> MemoryStatus {
        memory
    }
}

/// Never called by the chat tests; benchmarks have their own fake.
struct UnusedBenchmarkService: BenchmarkService {
    func benchmark(
        model: String,
        settings: BenchmarkSettings,
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult {
        Issue.record("unexpected benchmark")
        throw CancellationError()
    }
}

struct SilentThermalService: ThermalService {
    func pressureUpdates() -> AsyncStream<ThermalPressure> {
        AsyncStream { $0.finish() }
    }
}

/// Polls `condition` until it holds or about two seconds pass.
@MainActor
func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<200 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return false
}

@MainActor
struct ChatViewModelTests {
    let service = ControlledChatService()
    let viewModel: ChatViewModel

    init() {
        viewModel = Self.makeViewModel(service: service)
    }

    static func makeViewModel(service: ControlledChatService, memory: FixedMemory = FixedMemory()) -> ChatViewModel {
        ChatViewModel(
            chatService: service,
            benchmarkService: UnusedBenchmarkService(),
            catalog: FixedCatalog(),
            thermalService: SilentThermalService(),
            memoryService: memory
        )
    }

    private func send(_ text: String) {
        viewModel.draft = text
        viewModel.send()
    }

    @Test func streamsTokensIntoTheReply() async {
        send("Hi")
        #expect(await eventually { await service.replyCount == 1 })

        await service.send("Hel", toReply: 0)
        await service.send("lo", toReply: 0)
        await service.finishReply(0)

        #expect(await eventually { viewModel.status == .idle })
        #expect(viewModel.messages.map(\.text) == ["Hi", "Hello"])
        #expect(viewModel.backendLabel == "test-backend")
        #expect(await service.loadedModels == [PhoneModel.defaultAlias])
    }

    @Test func clearDuringReplyDropsLateTokens() async {
        send("First")
        #expect(await eventually { await service.replyCount == 1 })
        await service.send("Old", toReply: 0)
        #expect(await eventually { viewModel.messages.last?.text == "Old" })

        viewModel.clearConversation()
        #expect(viewModel.messages.isEmpty)

        // A token from the cleared turn arrives late: it must not reappear.
        await service.send(" late", toReply: 0)
        #expect(await eventually { await service.resetCount == 1 })

        send("Second")
        #expect(await eventually { await service.replyCount == 2 })
        await service.send("New", toReply: 1)
        await service.finishReply(1)

        #expect(await eventually { viewModel.status == .idle })
        #expect(viewModel.messages.map(\.text) == ["Second", "New"])
        // The model loads once; the second turn reuses it.
        #expect(await service.loadedModels.count == 1)
    }

    @Test func stopBeforeFirstTokenLeavesNoEmptyBubble() async {
        send("Hi")
        #expect(await eventually { viewModel.status == .generating })

        viewModel.stop()

        #expect(await eventually { viewModel.status == .idle })
        #expect(viewModel.messages.map(\.text) == ["Hi"])
    }
}

@MainActor
struct MemoryFitTests {
    @Test func refusesAModelThatCannotFitWithoutLoadingIt() async {
        let service = ControlledChatService()
        // 1.7B full precision needs ~2.8 GB; give the app 1.5 GB.
        let tight = FixedMemory(memory: MemoryStatus(footprintBytes: 150_000_000, availableBytes: 1_500_000_000))
        let viewModel = ChatViewModelTests.makeViewModel(service: service, memory: tight)
        viewModel.selectedModel = FixedCatalog.big.alias
        viewModel.draft = "Hi"

        viewModel.send()

        guard case .failed(let message) = viewModel.status else {
            Issue.record("expected a memory error, got \(viewModel.status)")
            return
        }
        #expect(message.contains("smollm2-1.7b"))
        #expect(viewModel.messages.isEmpty)
        #expect(viewModel.draft == "Hi", "the message is kept so the user can retry")
        #expect(await service.loadedModels.isEmpty)
    }

    @Test func loadsWhenItFits() async {
        let service = ControlledChatService()
        let viewModel = ChatViewModelTests.makeViewModel(service: service)
        viewModel.selectedModel = FixedCatalog.big.alias
        viewModel.draft = "Hi"

        viewModel.send()

        #expect(await eventually { await service.loadedModels == [FixedCatalog.big.alias] })
    }

    @Test func estimatesFollowTheStorageFormat() {
        let q4 = PhoneModel(alias: "a", params: "1.7B Q4_K_M", billions: 1.7)
        let full = PhoneModel(alias: "b", params: "1.7B", billions: 1.7)
        // 1.7e9 × bytes per parameter + 0.6 GB; compared loosely (floating point).
        #expect(q4.estimatedMemoryBytes.distance(to: 1_620_000_000).magnitude < 1_000)
        #expect(full.estimatedMemoryBytes.distance(to: 2_810_000_000).magnitude < 1_000)
    }

    @Test func memoryFreedByTheCurrentModelCounts() {
        let full = PhoneModel(alias: "b", params: "1.7B", billions: 1.7)
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
}
