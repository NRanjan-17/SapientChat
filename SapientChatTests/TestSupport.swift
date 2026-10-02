import Foundation
import SwiftData
import Synchronization
import Testing
@testable import SapientChat

/// Ordered record of what the fakes were asked to do, across services.
actor EventLog {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

/// A `ChatService` the test drives. With `autoReply`, every reply streams
/// those tokens and finishes; otherwise the test pushes tokens by hand.
actor ControlledChatService {
    private(set) var loadedModels: [String] = []
    private(set) var histories: [[ChatMessage]] = []
    private(set) var unloadCount = 0
    private var active: String?
    private var replies: [AsyncThrowingStream<String, any Error>.Continuation] = []
    private let autoReply: [String]?
    private let log: EventLog?

    init(autoReply: [String]? = nil, log: EventLog? = nil) {
        self.autoReply = autoReply
        self.log = log
    }

    var replyCount: Int { replies.count }

    func load(model: String) async throws -> String {
        if active != model {
            loadedModels.append(model)
            await log?.record("load \(model)")
        }
        active = model
        return "test-backend"
    }

    func loadedModel() async -> String? { active }

    func unload() async {
        unloadCount += 1
        active = nil
        await log?.record("unload")
    }

    func reply(to history: [ChatMessage]) async throws -> AsyncThrowingStream<String, any Error> {
        histories.append(history)
        await log?.record("reply \(active ?? "-")")
        let (stream, continuation) = AsyncThrowingStream<String, any Error>.makeStream()
        if let autoReply {
            autoReply.forEach { continuation.yield($0) }
            continuation.finish()
        }
        replies.append(continuation)
        return stream
    }

    func send(_ token: String, toReply index: Int) { replies[index].yield(token) }
    func finishReply(_ index: Int) { replies[index].finish() }
}

extension ControlledChatService: ChatService {}

/// A `BenchmarkService` that returns a canned result straight away.
struct InstantBenchmarkService: BenchmarkService {
    var log: EventLog?
    var decodeRate: @Sendable (String) -> Double = { _ in 20 }

    func benchmark(
        model: String,
        settings: BenchmarkSettings,
        onProgress: @escaping @Sendable (BenchmarkProgress) -> Void
    ) async throws -> BenchmarkResult {
        await log?.record("benchmark \(model)")
        let run = BenchmarkRunResult(
            index: 1, isWarmup: false, ttftMs: 100, elapsedMs: 1_000, tokens: settings.maxTokens,
            decodeTokensPerSecond: decodeRate(model), prefillTokensPerSecond: 50, hitEndOfTurn: false,
            footprintBytes: 1_000_000_000
        )
        onProgress(BenchmarkProgress(completed: 1, total: 1, lastRun: run))
        return BenchmarkResult(
            model: model, backend: "test", isMemoryMapped: true, contextLength: 3072, loadTimeMs: 1,
            promptTokens: 5, maxTokens: settings.maxTokens, warmupRuns: [], runs: [run], meanTtftMs: 100,
            meanDecodeTokensPerSecond: decodeRate(model), minDecodeTokensPerSecond: decodeRate(model),
            maxDecodeTokensPerSecond: decodeRate(model), meanPrefillTokensPerSecond: 50,
            peakFootprintBytes: 1, thermalStart: "nominal", thermalEnd: "nominal", cancelled: false,
            engineVersion: "test", method: "test", isSimulator: true
        )
    }
}

enum TestModels {
    static let small = PhoneModel(alias: PhoneModel.defaultAlias, repoId: "org/small-GGUF", params: "135M Q4_K_M", billions: 0.135)
    static let big = PhoneModel(alias: "openhorizon/smollm2-1.7b", repoId: "org/big", params: "1.7B", billions: 1.7)
}

struct FixedCatalog: ModelCatalogService {
    func chatModels() -> [PhoneModel] { [TestModels.small, TestModels.big] }
}

struct FixedMemory: MemoryService {
    var memory = MemoryStatus(footprintBytes: 200_000_000, availableBytes: 3_000_000_000)
    func status() -> MemoryStatus { memory }
}

/// Plenty of memory except for the 1.7B model.
let tightMemory = FixedMemory(memory: MemoryStatus(footprintBytes: 150_000_000, availableBytes: 1_500_000_000))

struct SilentThermalService: ThermalService {
    func pressureUpdates() -> AsyncStream<ThermalPressure> { AsyncStream { $0.finish() } }
}

/// In-memory downloads keyed by repo id.
final class FakeStorage: ModelStorageService, Sendable {
    private let state: Mutex<[String: UInt64]>
    private let log: EventLog?

    init(downloads: [String: UInt64] = [:], log: EventLog? = nil) {
        state = Mutex(downloads)
        self.log = log
    }

    func download(forRepo repoId: String) -> ModelDownload {
        state.withLock { $0[repoId] }.map { .downloaded(bytes: $0) } ?? .notDownloaded
    }

    func deleteDownload(forRepo repoId: String) throws {
        _ = state.withLock { $0.removeValue(forKey: repoId) }
        if let log { Task { await log.record("delete \(repoId)") } }
    }

    func deleteAllDownloads() throws {
        state.withLock { $0.removeAll() }
    }

    func totalDownloadBytes() -> UInt64 {
        state.withLock { $0.values.reduce(0, +) }
    }
}

@MainActor
func makeServices(
    chat: ControlledChatService,
    benchmark: any BenchmarkService = InstantBenchmarkService(),
    memory: FixedMemory = FixedMemory(),
    storage: FakeStorage = FakeStorage()
) -> AppServices {
    AppServices(
        chat: chat, benchmark: benchmark, catalog: FixedCatalog(),
        thermal: SilentThermalService(), memory: memory, storage: storage
    )
}

/// A fresh in-memory SwiftData container (each test gets its own).
@MainActor
func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Conversation.self, StoredMessage.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    )
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
