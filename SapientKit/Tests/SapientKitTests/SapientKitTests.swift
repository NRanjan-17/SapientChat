import Foundation
import Synchronization
import Testing
@testable import SapientKit

/// Answers handoff URLs the way SapientChat does: reads the request, then
/// opens the callback with `?status=…&body=<base64url>` appended.
final class FakeSapientApp: Sendable {
    let requests = Mutex<[(path: String, method: String, body: Data?, source: String?)]>([])
    let reply: @Sendable (String) -> (status: Int, json: String)
    let transport = Mutex<HandoffTransport?>(nil)

    init(reply: @escaping @Sendable (String) -> (status: Int, json: String)) {
        self.reply = reply
    }

    func open(_ url: URL) async -> Bool {
        guard url.scheme == "sapient", url.host() == "x-callback-url", url.path() == "/request",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return false }
        let query = Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
        let path = query["path"] ?? ""
        requests.withLock { $0.append((path, query["method"] ?? "", query["body"].flatMap(Base64URL.decode), query["x-source"])) }
        let (status, json) = reply(path)
        var callback = URLComponents(string: status < 400 ? query["x-success"]! : query["x-error"]!)!
        callback.queryItems = (callback.queryItems ?? []) + [
            URLQueryItem(name: "status", value: String(status)),
            URLQueryItem(name: "body", value: Base64URL.encode(Data(json.utf8))),
        ]
        let transport = transport.withLock { $0 }
        Task { transport?.handle(callback.url!) }
        return true
    }
}

struct HandoffTests {
    private func client(_ app: FakeSapientApp) -> SapientClient {
        let transport = HandoffTransport(callbackScheme: "myapp", appName: "My App") { await app.open($0) }
        app.transport.withLock { $0 = transport }
        return SapientClient(transport: transport)
    }

    @Test func chatRoundTripsThroughTheHandoff() async throws {
        let app = FakeSapientApp { _ in
            (200, #"{"id":"c1","model":"m","choices":[{"index":0,"message":{"role":"assistant","content":"Hi!"},"finish_reason":"stop"}],"usage":{"prompt_tokens":0,"completion_tokens":2,"total_tokens":2}}"#)
        }
        let reply = try await client(app).chat([.system("Be brief"), .user("Hello")], model: "m", maxTokens: 20)
        #expect(reply.text == "Hi!")
        #expect(reply.usage.completionTokens == 2)
        let sent = try #require(app.requests.withLock { $0.first })
        #expect(sent.path == "/v1/chat/completions")
        #expect(sent.method == "POST")
        #expect(sent.source == "My App")
        let body = try #require(sent.body.flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] })
        #expect(body["max_tokens"] as? Int == 20)
        #expect((body["messages"] as? [[String: Any]])?.count == 2)
    }

    @Test func apiErrorsBecomeSapientErrors() async {
        let app = FakeSapientApp { _ in (400, #"{"error":{"message":"Model 'x' isn't available","type":"invalid_request_error"}}"#) }
        await #expect(throws: SapientError.api(status: 400, message: "Model 'x' isn't available")) {
            try await client(app).load("x")
        }
    }

    @Test func cancellingInSapientChatThrowsCancelled() async {
        let transport = HandoffTransport(callbackScheme: "myapp") { _ in true }
        let sapient = SapientClient(transport: transport)
        let reply = Task { try await sapient.health() }
        // Wait for the request to be pending, then cancel it as SapientChat would.
        try? await Task.sleep(for: .milliseconds(50))
        let url = transport.requestURL(id: "unused", method: "GET", path: "/v1/health", body: nil)
        #expect(url.absoluteString.hasPrefix("sapient://x-callback-url/request?"))
        let pendingID = transport.pendingIDsForTesting.first ?? ""
        #expect(sapient.handle(URL(string: "myapp://sapient-callback/cancel?id=\(pendingID)")!))
        await #expect(throws: SapientError.cancelled) { try await reply.value }
    }

    @Test func notInstalledFailsFast() async {
        let sapient = SapientClient(transport: HandoffTransport(callbackScheme: "myapp") { _ in false })
        await #expect(throws: SapientError.unavailable("SapientChat isn't installed on this device.")) {
            try await sapient.health()
        }
    }

    @Test func ignoresOtherURLs() {
        let sapient = SapientClient(transport: HandoffTransport(callbackScheme: "myapp") { _ in true })
        #expect(!sapient.handle(URL(string: "myapp://settings")!))
        #expect(!sapient.handle(URL(string: "other://sapient-callback/success?id=1")!))
    }
}

/// Stubs URLSession responses by path.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var responses: [String: (status: Int, contentType: String, body: String)] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let stub = Self.responses[request.url!.path()] ?? (404, "application/json", #"{"error":{"message":"No route"}}"#)
        let response = HTTPURLResponse(url: request.url!, statusCode: stub.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": stub.contentType])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(stub.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct HTTPTests {
    private func client() -> SapientClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let transport = HTTPTransport(baseURL: URL(string: "http://phone.local:11435")!, session: URLSession(configuration: configuration))
        return SapientClient(transport: transport)
    }

    @Test func streamsChatPieces() async throws {
        StubProtocol.responses["/v1/chat/completions"] = (200, "text/event-stream", """
            data: {"choices":[{"index":0,"delta":{"role":"assistant"}}]}

            data: {"choices":[{"index":0,"delta":{"content":"Hel"}}]}

            data: {"choices":[{"index":0,"delta":{"content":"lo"}}]}

            data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

            data: [DONE]


            """)
        var pieces: [String] = []
        for try await piece in client().streamChat([.user("Hi")]) { pieces.append(piece) }
        #expect(pieces == ["Hel", "lo"])
    }

    @Test func readsTheCatalogAndHealth() async throws {
        StubProtocol.responses["/v1/catalog"] = (200, "application/json", """
            {"object":"list","data":[{"id":"openhorizon/qwen2.5-0.5b","name":"qwen2.5-0.5b","params":"0.5B","format":"Full precision",\
            "parameter_billions":0.5,"estimated_memory_bytes":1250000000,"downloaded":true,"downloaded_bytes":990000000,\
            "loaded":false,"fits":true}],"resident_models":[],"max_resident_models":4}
            """)
        StubProtocol.responses["/v1/health"] = (200, "application/json", """
            {"status":"ok","version":"0.6.6","loaded_model":null,"resident_models":[],"audio_models":[],"vla_models":[],\
            "max_resident_models":4,"device":{"footprint_bytes":1,"available_bytes":2,"thermal":"nominal"}}
            """)
        let catalog = try await client().catalog()
        #expect(catalog.models.first?.downloaded == true)
        #expect(catalog.maxResidentModels == 4)
        let health = try await client().health()
        #expect(health.device?.thermal == "nominal")
    }

    @Test func pingsAndFiltersTheCatalog() async throws {
        StubProtocol.responses["/v1/ping"] = (200, "application/json", #"{"status":"ok","version":"0.6.6"}"#)
        let a = #"{"id":"a","name":"a","params":"0.5B","format":"4-bit","parameter_billions":0.5,"estimated_memory_bytes":1,"downloaded":true,"downloaded_bytes":1,"loaded":true,"fits":true}"#
        let b = #"{"id":"b","name":"b","params":"1.5B","format":"4-bit","parameter_billions":1.5,"estimated_memory_bytes":1,"downloaded":false,"downloaded_bytes":0,"loaded":false,"fits":true}"#
        StubProtocol.responses["/v1/catalog"] = (200, "application/json",
            #"{"object":"list","data":["# + a + "," + b + #"],"resident_models":["a"],"max_resident_models":4}"#)
        #expect(try await client().ping().version == "0.6.6")
        #expect(try await client().catalog(.downloaded).map(\.id) == ["a"])
        #expect(try await client().catalog(.available).map(\.id) == ["b"])
        #expect(try await client().catalog(.loaded).map(\.id) == ["a"])
    }

    @Test func downloadProgressStreams() async throws {
        StubProtocol.responses["/v1/models/download"] = (200, "text/event-stream", """
            data: {"model":"m","status":"downloading","downloaded_bytes":50,"total_bytes":100}

            data: {"model":"m","status":"downloaded","downloaded_bytes":100,"total_bytes":100}

            data: [DONE]


            """)
        var fractions: [Double?] = []
        for try await event in client().downloadWithProgress("m") { fractions.append(event.fraction) }
        #expect(fractions == [0.5, 1])
    }
}
