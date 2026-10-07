import Foundation
import SwiftData
import Testing
@testable import SapientChat

@MainActor
struct RequestLogTests {
    private func makeServer(
        reply: [String] = ["Hel", "lo", "!"],
        store: InMemoryRequestLogStore? = nil,
        defaults: UserDefaults = UserDefaults(suiteName: "log-\(UUID().uuidString)")!
    ) -> (ServerViewModel, ServeRouter, InMemoryRequestLogStore) {
        let store = store ?? InMemoryRequestLogStore()
        let router = ServeRouter(
            services: makeServices(chat: ControlledChatService(autoReply: reply)),
            device: DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        )
        let server = ServerViewModel(router: router, defaults: defaults, keeper: FakeKeeper(), requestLog: store)
        return (server, router, store)
    }

    private func chat(_ router: ServeRouter, stream: Bool) async throws {
        let request = HTTPRequest(method: "POST", path: "/v1/chat/completions", body: Data("""
            {"model":"\(TestModels.small.alias)","stream":\(stream),"messages":[{"role":"system","content":"Be brief"},{"role":"user","content":"Hi"}]}
            """.utf8))
        let response = await router.handle(request, source: "Shortcuts")
        if case .stream(let chunks) = response.body {
            for try await _ in chunks {}
        }
    }

    @Test func aChatIsSavedWithItsPromptReplyAndSpeed() async throws {
        let (server, router, store) = makeServer()
        try await chat(router, stream: false)

        let entry = try #require(server.log.first)
        #expect(entry.status == 200)
        #expect(entry.source == "Shortcuts")
        #expect(entry.model == TestModels.small.alias)
        #expect(entry.messages.map(\.role) == ["system", "user"])
        #expect(entry.promptPreview == "Hi")
        #expect(entry.reply == "Hello!")
        #expect(entry.tokens == 3)
        #expect(entry.durationMs != nil)
        #expect(store.stored == [entry], "saved for the next launch")
    }

    @Test func aStreamedReplyIsSavedWhenTheStreamEnds() async throws {
        let (server, router, _) = makeServer()
        try await chat(router, stream: true)
        #expect(await eventually { server.log.first?.reply == "Hello!" })
        #expect(server.log.count == 1)
    }

    @Test func otherRequestsKeepTheirBodies() async throws {
        let (server, router, _) = makeServer()
        _ = await router.handle(HTTPRequest(method: "GET", path: "/v1/ping"))
        let entry = try #require(server.log.first)
        #expect(entry.reply == nil && entry.messages.isEmpty)
        #expect(entry.responseBody?.contains(#""status" : "ok""#) == true)
    }

    @Test func errorsAreReadable() async throws {
        let (server, router, _) = makeServer()
        _ = await router.handle(HTTPRequest(method: "GET", path: "/nope"))
        #expect(server.log.first?.status == 404)
        #expect(server.log.first?.error?.contains("No route") == true)
    }

    @Test func withSavingOffOnlyWhatHappenedIsKept() async throws {
        let (server, router, store) = makeServer()
        server.savesContent = false
        try await chat(router, stream: false)
        let entry = try #require(store.stored.first)
        #expect(entry.messages.isEmpty && entry.reply == nil && entry.requestBody == nil && entry.responseBody == nil)
        #expect(entry.status == 200 && entry.tokens == 3, "metrics stay")
    }

    @Test func theLogComesBackAfterARelaunchAndClears() async throws {
        let store = InMemoryRequestLogStore()
        let (first, router, _) = makeServer(store: store)
        try await chat(router, stream: false)
        let (second, _, _) = makeServer(store: store)
        #expect(second.log.map(\.id) == first.log.map(\.id))
        second.clearLog()
        #expect(second.log.isEmpty && store.stored.isEmpty)
    }

    @Test func keepsOnlyTheNewest() {
        let store = InMemoryRequestLogStore()
        for index in 0..<5 {
            store.insert(RequestLogEntry(date: Date(timeIntervalSince1970: Double(index)), method: "GET", path: "/\(index)"))
        }
        store.trim(keeping: 2)
        #expect(store.entries(limit: 10).map(\.path) == ["/4", "/3"])
    }

    @Test func swiftDataRoundTrips() throws {
        let container = try ModelContainer(
            for: RequestRecord.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let store = SwiftDataRequestLogStore(context: container.mainContext)
        var entry = RequestLogEntry(date: .now, method: "POST", path: "/v1/chat/completions")
        entry.messages = [.init(role: "user", text: "Hi")]
        entry.reply = "Hello"
        store.insert(entry)
        #expect(store.entries(limit: 10) == [entry])
        store.deleteAll()
        #expect(store.entries(limit: 10).isEmpty)
    }

    @Test func longBodiesAreCut() {
        let text = RequestLogEntry.text(of: Data(String(repeating: "a", count: RequestLogEntry.maxBodyCharacters + 10).utf8))
        #expect(text?.hasSuffix("(cut at 64 KB)") == true)
        #expect(RequestLogEntry.text(of: Data()) == nil)
    }
}
