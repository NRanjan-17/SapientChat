import Foundation
import Testing
@testable import SapientChat

struct HTTPRequestParserTests {
    @Test func parsesARequestWithABody() throws {
        let raw = "POST /v1/chat/completions?x=1 HTTP/1.1\r\nHost: a\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}"
        guard case .complete(let request) = HTTPRequestParser.parse(Data(raw.utf8)) else {
            Issue.record("expected a complete request"); return
        }
        #expect(request.method == "POST")
        #expect(request.path == "/v1/chat/completions")
        #expect(request.query["x"] == "1")
        #expect(request.header("content-type") == "application/json")
        #expect(request.body == Data("{}".utf8))
    }

    @Test func waitsForTheWholeBody() {
        let raw = "POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}"
        guard case .incomplete = HTTPRequestParser.parse(Data(raw.utf8)) else {
            Issue.record("expected incomplete"); return
        }
    }

    @Test func rejectsChunkedBodiesAndGarbage() {
        let chunked = "POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"
        guard case .invalid(411, _) = HTTPRequestParser.parse(Data(chunked.utf8)) else {
            Issue.record("expected 411"); return
        }
        guard case .invalid(400, _) = HTTPRequestParser.parse(Data("nonsense\r\n\r\n".utf8)) else {
            Issue.record("expected 400"); return
        }
    }
}

struct StopSequenceFilterTests {
    @Test func stopsBeforeASequenceSplitAcrossFragments() {
        var filter = StopSequenceFilter(["END"])
        var out = filter.feed("Hello E")
        out += filter.feed("N")
        #expect(out == "Hello ")
        out += filter.feed("D and more")
        #expect(out == "Hello ")
        #expect(filter.isStopped)
        #expect(filter.flush().isEmpty)
    }

    @Test func releasesHeldTextThatTurnsOutNotToMatch() {
        var filter = StopSequenceFilter(["END"])
        var out = filter.feed("an E")
        out += filter.feed("gg")
        out += filter.flush()
        #expect(out == "an Egg")
        #expect(!filter.isStopped)
    }

    @Test func passesThroughWithoutStops() {
        var filter = StopSequenceFilter([])
        #expect(filter.feed("abc") == "abc")
    }
}

@MainActor
struct ServeRouterTests {
    private func makeRouter(reply: [String] = ["Hel", "lo", "!"], storage: FakeStorage = downloadedStorage())
        -> (ServeRouter, ControlledChatService)
    {
        let chat = ControlledChatService(autoReply: reply)
        let services = makeServices(chat: chat, storage: storage)
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        return (ServeRouter(services: services, device: device), chat)
    }

    private func post(_ path: String, _ json: String, headers: [String: String] = [:]) -> HTTPRequest {
        HTTPRequest(method: "POST", path: path, headers: headers, body: Data(json.utf8))
    }

    private func body(_ response: HTTPResponse) async throws -> String {
        switch response.body {
        case .data(let data):
            return String(decoding: data, as: UTF8.self)
        case .stream(let chunks):
            var data = Data()
            for try await chunk in chunks { data.append(chunk) }
            return String(decoding: data, as: UTF8.self)
        }
    }

    @Test func chatCompletionAnswersWithTheWholeReply() async throws {
        let (router, chat) = makeRouter()
        let response = await router.handle(post("/v1/chat/completions", """
            {"model":"\(TestModels.small.alias)","messages":[{"role":"system","content":"Be brief"},{"role":"user","content":"Hi"}]}
            """))
        #expect(response.status == 200)
        let reply = try JSONSerialization.jsonObject(with: Data(try await body(response).utf8)) as? [String: Any]
        let choice = (reply?["choices"] as? [[String: Any]])?.first
        #expect((choice?["message"] as? [String: Any])?["content"] as? String == "Hello!")
        #expect(choice?["finish_reason"] as? String == "stop")
        #expect((reply?["usage"] as? [String: Any])?["completion_tokens"] as? Int == 3)
        #expect(await chat.histories.first?.map(\.role) == [.system, .user])
    }

    @Test func streamingSendsRoleThenContentThenUsageThenDone() async throws {
        let (router, _) = makeRouter()
        let response = await router.handle(post("/v1/chat/completions", """
            {"model":"smollm2-135m-q4","stream":true,"messages":[{"role":"user","content":"Hi"}]}
            """))
        #expect(response.contentType == "text/event-stream")
        let events = try await body(response).components(separatedBy: "\n\n").filter { !$0.isEmpty }
        #expect(events.count == 6) // role, 3 content, final, [DONE]
        #expect(events.first?.contains(#""role":"assistant""#) == true)
        #expect(events[4].contains(#""finish_reason":"stop""#) && events[4].contains(#""usage""#))
        #expect(events.last == "data: [DONE]")
    }

    @Test func maxTokensAndStopEndTheReplyEarly() async throws {
        let (router, _) = makeRouter(reply: ["one ", "two ", "three"])
        let limited = await router.handle(post("/v1/completions", #"{"model":"smollm2-135m-q4","prompt":"Count","max_tokens":2}"#))
        #expect(try await body(limited).contains(#""text":"one two ""#))
        let stopped = await router.handle(post("/v1/completions", #"{"model":"smollm2-135m-q4","prompt":"Count","stop":"two"}"#))
        #expect(try await body(stopped).contains(#""text":"one ""#))
    }

    @Test func noModelFallsBackToTheLoadedOneOrFails() async throws {
        let (router, chat) = makeRouter()
        let missing = await router.handle(post("/v1/chat/completions", #"{"messages":[{"role":"user","content":"Hi"}]}"#))
        #expect(missing.status == 400)
        #expect(try await body(missing).contains("model_not_found"))

        _ = try await chat.load(model: TestModels.small.alias)
        let fallback = await router.handle(post("/v1/chat/completions", #"{"messages":[{"role":"user","content":"Hi"}]}"#))
        #expect(fallback.status == 200)
        #expect(await chat.replyModels.last == TestModels.small.alias)
    }

    @Test func modelsAndHealthReportDownloadedAndResidentModels() async throws {
        let (router, chat) = makeRouter(storage: FakeStorage(downloads: [TestModels.small.repoId: 100]))
        _ = try await chat.load(model: TestModels.small.alias)
        let models = try await body(router.handle(HTTPRequest(method: "GET", path: "/v1/models")))
        #expect(models.contains(#""id":"\#(TestModels.small.alias)""#))
        #expect(!models.contains(TestModels.big.alias))
        #expect(models.contains(#""active_model":"\#(TestModels.small.alias)""#))
        let health = try await body(router.handle(HTTPRequest(method: "GET", path: "/v1/health")))
        #expect(health.contains(#""status":"ok""#) && health.contains(#""loaded_model""#))
    }

    @Test func rejectsUnknownModelsRolesAndMissingKeys() async throws {
        let (router, _) = makeRouter()
        #expect(await router.handle(post("/v1/chat/completions", #"{"model":"nope","messages":[{"role":"user","content":"Hi"}]}"#)).status == 400)
        #expect(await router.handle(post("/v1/chat/completions", #"{"model":"smollm2-135m-q4","messages":[{"role":"tool","content":"x"}]}"#)).status == 400)
        #expect(await router.handle(HTTPRequest(method: "POST", path: "/v1/audio/speech")).status == 501)
        #expect(await router.handle(HTTPRequest(method: "GET", path: "/nope")).status == 404)

        router.apiKey = "secret"
        #expect(await router.handle(HTTPRequest(method: "GET", path: "/v1/health")).status == 401)
        let authorized = HTTPRequest(method: "GET", path: "/v1/health", headers: ["authorization": "Bearer secret"])
        #expect(await router.handle(authorized).status == 200)
    }
}

/// The real listener on loopback, called with URLSession.
@MainActor
struct HTTPServerTests {
    @Test func servesChatCompletionsOverTheNetwork() async throws {
        let chat = ControlledChatService(autoReply: ["Hi", " there"])
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: makeServices(chat: chat), device: device)
        let server = HTTPServer()
        let port = UInt16.random(in: 20_000...40_000)
        let (states, sink) = AsyncStream<HTTPServer.State>.makeStream()
        server.start(.init(port: port, allowsNetwork: false, bonjourName: nil), handler: { await router.handle($0) }) {
            sink.yield($0)
        }
        defer { server.stop() }
        for await state in states {
            if state == .running { break }
            if case .failed(let message) = state { Issue.record("listener failed: \(message)"); return }
        }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"model":"smollm2-135m-q4","stream":true,"messages":[{"role":"user","content":"Hi"}]}"#.utf8)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        var lines: [String] = []
        for try await line in bytes.lines where line.hasPrefix("data: ") {
            lines.append(line)
        }
        #expect(lines.count == 5) // role, 2 content, final, [DONE]
        #expect(lines.last == "data: [DONE]")
    }
}

@MainActor
struct ModelManagementAPITests {
    private func makeRouter(storage: FakeStorage = FakeStorage()) -> (ServeRouter, ControlledChatService, FakeStorage) {
        let chat = ControlledChatService(autoReply: ["ok"])
        let services = makeServices(chat: chat, storage: storage)
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        return (ServeRouter(services: services, device: device), chat, storage)
    }

    private func post(_ path: String, _ json: String = "") -> HTTPRequest {
        HTTPRequest(method: "POST", path: path, body: Data(json.utf8))
    }

    private func json(_ response: HTTPResponse) async throws -> [String: Any] {
        var data = Data()
        switch response.body {
        case .data(let body): data = body
        case .stream(let chunks): for try await chunk in chunks { data.append(chunk) }
        }
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test func catalogListsEveryModelWithItsState() async throws {
        let (router, chat, storage) = makeRouter()
        storage.complete(TestModels.small.repoId, bytes: 100)
        _ = try await chat.load(model: TestModels.small.alias)
        let catalog = try await json(router.handle(HTTPRequest(method: "GET", path: "/v1/catalog")))
        let models = try #require(catalog["data"] as? [[String: Any]])
        #expect(models.count == 2)
        let small = try #require(models.first { $0["id"] as? String == TestModels.small.alias })
        #expect(small["downloaded"] as? Bool == true && small["loaded"] as? Bool == true)
        let big = try #require(models.first { $0["id"] as? String == TestModels.big.alias })
        #expect(big["downloaded"] as? Bool == false && big["loaded"] as? Bool == false)
        #expect(catalog["max_resident_models"] as? Int == 4)
    }

    @Test func downloadLoadUnloadDelete() async throws {
        let (router, chat, storage) = makeRouter()
        let model = #"{"model":"\#(TestModels.small.alias)"}"#

        let downloaded = try await json(router.handle(post("/v1/models/download", model)))
        #expect(downloaded["status"] as? String == "downloaded")
        #expect(storage.download(forRepo: TestModels.small.repoId).isDownloaded)
        #expect(await chat.loadedModels().isEmpty, "download alone doesn't load")

        let loaded = try await json(router.handle(post("/v1/models/load", model)))
        #expect(loaded["status"] as? String == "loaded")
        #expect(loaded["backend"] as? String == "test-backend")
        #expect(loaded["resident_models"] as? [String] == [TestModels.small.alias])

        let unloaded = try await json(router.handle(post("/v1/models/unload")))
        #expect(unloaded["status"] as? String == "unloaded")
        #expect(await chat.loadedModels().isEmpty)

        let deleted = try await json(router.handle(post("/v1/models/delete", model)))
        #expect(deleted["status"] as? String == "deleted")
        #expect(!storage.download(forRepo: TestModels.small.repoId).isDownloaded)
    }

    @Test func downloadStreamsProgressEvents() async throws {
        let (router, _, _) = makeRouter()
        let response = await router.handle(post("/v1/models/download", #"{"model":"smollm2-135m-q4","stream":true}"#))
        guard case .stream(let chunks) = response.body else { Issue.record("expected a stream"); return }
        var text = ""
        for try await chunk in chunks { text += String(decoding: chunk, as: UTF8.self) }
        let events = text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        #expect(events.filter { $0.contains(#""status":"downloading""#) }.count == 4)
        #expect(events.dropLast().last?.contains(#""status":"downloaded""#) == true)
        #expect(events.last == "data: [DONE]")
    }

    @Test func modelActionsNeedAKnownModel() async throws {
        let (router, _, _) = makeRouter()
        #expect(await router.handle(post("/v1/models/load")).status == 400)
        #expect(await router.handle(post("/v1/models/load", #"{"model":"nope"}"#)).status == 400)
        #expect(await router.handle(post("/v1/models/load", "{bad")).status == 422)
    }
}

@MainActor
struct HandoffTests {
    /// Built exactly as SapientKit's `HandoffTransport.requestURL` builds it.
    private func handoffURL(path: String, body: String?, key: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = "sapient"
        components.host = "x-callback-url"
        components.path = "/request"
        var items = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "method", value: body == nil ? "GET" : "POST"),
            URLQueryItem(name: "x-success", value: "myapp://sapient-callback/success?id=42"),
            URLQueryItem(name: "x-error", value: "myapp://sapient-callback/error?id=42"),
            URLQueryItem(name: "x-cancel", value: "myapp://sapient-callback/cancel?id=42"),
            URLQueryItem(name: "x-source", value: "My App"),
        ]
        if let body { items.append(URLQueryItem(name: "body", value: Base64URL.encode(Data(body.utf8)))) }
        if let key { items.append(URLQueryItem(name: "key", value: key)) }
        components.queryItems = items
        return components.url!
    }

    @Test func parsesASapientKitRequestAndTurnsStreamingOff() throws {
        let handoff = try HandoffRequest(url: handoffURL(
            path: "/v1/chat/completions", body: #"{"stream":true,"messages":[{"role":"user","content":"Hi"}]}"#, key: "k"
        ))
        #expect(handoff.request.method == "POST")
        #expect(handoff.request.path == "/v1/chat/completions")
        #expect(handoff.request.header("authorization") == "Bearer k")
        #expect(handoff.source == "My App")
        let body = try JSONSerialization.jsonObject(with: handoff.request.body) as? [String: Any]
        #expect(body?["stream"] as? Bool == false)
    }

    @Test func rejectsOtherURLs() {
        #expect(throws: HandoffRequest.ParseError.notAHandoff) { try HandoffRequest(url: URL(string: "sapient://chat")!) }
        #expect(throws: HandoffRequest.ParseError.missingPath) {
            try HandoffRequest(url: URL(string: "sapient://x-callback-url/request?path=/etc")!)
        }
        #expect(throws: HandoffRequest.ParseError.badBody) {
            try HandoffRequest(url: URL(string: "sapient://x-callback-url/request?path=/v1/models&body=!!!")!)
        }
    }

    @Test func runsTheRequestAndOpensTheCallbackWithTheResult() async throws {
        let chat = ControlledChatService(autoReply: ["Hel", "lo"])
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: makeServices(chat: chat), device: device)
        var opened: [URL] = []
        let handoff = HandoffViewModel(router: router) { url in opened.append(url); return true }

        handoff.open(handoffURL(
            path: "/v1/chat/completions",
            body: #"{"model":"smollm2-135m-q4","stream":true,"messages":[{"role":"user","content":"Hi"}]}"#
        ))
        #expect(handoff.state == .running(source: "My App", path: "/v1/chat/completions"))
        #expect(await eventually { !opened.isEmpty })
        #expect(handoff.state == .idle)

        let callback = try #require(opened.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(callback.path == "/success")
        let query = Dictionary((callback.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        #expect(query["id"] == "42" && query["status"] == "200")
        let body = try #require(query["body"].flatMap(Base64URL.decode))
        let reply = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let message = ((reply?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String
        #expect(message == "Hello")
    }

    @Test func failuresGoToTheErrorCallback() async throws {
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: makeServices(chat: ControlledChatService()), device: device)
        var opened: [URL] = []
        let handoff = HandoffViewModel(router: router) { url in opened.append(url); return true }
        handoff.open(handoffURL(path: "/v1/models/load", body: #"{"model":"nope"}"#))
        #expect(await eventually { !opened.isEmpty })
        let callback = try #require(opened.first.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(callback.path == "/error")
        #expect(callback.queryItems?.contains { $0.name == "status" && $0.value == "400" } == true)
        #expect(callback.queryItems?.contains { $0.name == "error" && $0.value?.contains("nope") == true } == true)
    }

    @Test func cancellingOpensTheCancelCallback() async {
        let chat = ControlledChatService() // never replies
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: makeServices(chat: chat), device: device)
        var opened: [URL] = []
        let handoff = HandoffViewModel(router: router) { url in opened.append(url); return true }
        handoff.open(handoffURL(path: "/v1/chat/completions", body: #"{"model":"smollm2-135m-q4","messages":[{"role":"user","content":"Hi"}]}"#))
        handoff.cancel()
        #expect(handoff.state == .idle)
        #expect(await eventually { opened.first?.path() == "/cancel" })
    }
}
