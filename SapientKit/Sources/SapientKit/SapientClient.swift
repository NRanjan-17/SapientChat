// SPDX-License-Identifier: MIT
// Copyright (c) 2026 OpenHorizon Labs Pvt Ltd — SapientKit (see SapientKit/LICENSE)

import Foundation

/// Calls SapientStudio, which loads and runs models on the device, from any
/// app: see the catalog, download, load and unload models, and chat.
///
///     // Another device, or beside SapientStudio on iPad:
///     let sapient = SapientClient.http(URL(string: "http://192.168.1.20:11435")!)
///
///     // Same iPhone (SapientStudio comes to the front for each request):
///     let sapient = SapientClient.handoff(callbackScheme: "myapp", appName: "My App")
///     // …and in your App: .onOpenURL { sapient.handle($0) }
///
///     // Either, whichever works:
///     let sapient = SapientClient.automatic(callbackScheme: "myapp", appName: "My App")
///
///     try await sapient.load("openhorizon/qwen2.5-0.5b")
///     let reply = try await sapient.chat([.user("Hi!")])
public final class SapientClient: Sendable {
    public let transport: any SapientTransport

    /// SapientStudio's API server port.
    public static let defaultPort = 11435

    public init(transport: any SapientTransport) {
        self.transport = transport
    }

    /// Over HTTP, at an address the API Server screen shows. `appName` is
    /// what Sapient's request log calls you (your app's name by default).
    public static func http(_ baseURL: URL, apiKey: String? = nil, appName: String? = SapientClient.appName) -> SapientClient {
        SapientClient(transport: HTTPTransport(baseURL: baseURL, apiKey: apiKey, clientName: appName))
    }

    /// This app's name (display name, else bundle name, else process name),
    /// sent so Sapient's request log can say which app called.
    public static var appName: String? {
        let info = Bundle.main.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String) ?? ProcessInfo.processInfo.processName
        return name.isEmpty ? nil : name
    }

    /// Percent-encodes what a header can't carry (non-ASCII, `%`); Sapient
    /// decodes it.
    static func headerValue(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var allowed = CharacterSet(charactersIn: " !#$&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[]^_`abcdefghijklmnopqrstuvwxyz{|}~")
        allowed.remove(charactersIn: "%")
        return trimmed.addingPercentEncoding(withAllowedCharacters: allowed)
    }

    #if canImport(UIKit)
    /// By URL handoff to SapientStudio on this device.
    public static func handoff(callbackScheme: String, appName: String? = nil, apiKey: String? = nil) -> SapientClient {
        SapientClient(transport: HandoffTransport(callbackScheme: callbackScheme, appName: appName ?? Self.appName, apiKey: apiKey))
    }

    /// The server on this device when it answers (SapientStudio in front, e.g.
    /// beside your app on iPad), otherwise a URL handoff.
    public static func automatic(
        callbackScheme: String, appName: String? = nil, apiKey: String? = nil,
        baseURL: URL = URL(string: "http://127.0.0.1:\(defaultPort)")!
    ) -> SapientClient {
        SapientClient(transport: FallbackTransport(
            primary: HTTPTransport(baseURL: baseURL, apiKey: apiKey, clientName: appName ?? Self.appName),
            fallback: HandoffTransport(callbackScheme: callbackScheme, appName: appName ?? Self.appName, apiKey: apiKey)
        ))
    }
    #endif

    /// Completes a handoff from the callback URL SapientStudio opened. Call it
    /// from `.onOpenURL`; returns false for URLs that aren't SapientStudio's.
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        switch transport {
        case let handoff as HandoffTransport: handoff.handle(url)
        case let fallback as FallbackTransport: fallback.fallback.handle(url)
        default: false
        }
    }

    // MARK: Status and models

    public func health() async throws -> Health {
        try await get("/v1/health")
    }

    /// Whether SapientStudio answers, without touching any model.
    public func ping() async throws -> Ping {
        try await get("/v1/ping")
    }

    /// Every model the device offers, with download, memory and load state.
    public func catalog() async throws -> Catalog {
        try await get("/v1/catalog")
    }

    /// Only the models that are `status`: not downloaded yet, downloaded, or in memory.
    public func catalog(_ status: Catalog.Status) async throws -> [Catalog.Model] {
        try await catalog().data.filter(status.includes)
    }

    /// The downloaded models.
    public func models() async throws -> ModelList {
        try await get("/v1/models")
    }

    /// A model's temperature and context window.
    public func settings(for model: String) async throws -> ModelSettings {
        let encoded = model.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? model
        return try await get("/v1/models/settings?model=\(encoded)")
    }

    /// Changes a model's temperature and/or context window; `.keep` leaves
    /// one as it is. A model in memory is reloaded once so the next request
    /// uses the new settings.
    ///
    ///     try await sapient.updateSettings("openhorizon/qwen2.5-1.5b", temperature: .set(0.7))
    ///     try await sapient.updateSettings(model, temperature: .useDefault, contextWindow: .set(4096))
    @discardableResult
    public func updateSettings(
        _ model: String,
        temperature: SettingChange<Double> = .keep,
        contextWindow: SettingChange<Int> = .keep
    ) async throws -> ModelSettings {
        var body: [String: Any] = ["model": model]
        switch temperature {
        case .keep: break
        case .useDefault: body["temperature"] = NSNull()
        case .set(let value): body["temperature"] = value
        }
        switch contextWindow {
        case .keep: break
        case .useDefault: body["context_window"] = NSNull()
        case .set(let value): body["context_window"] = value
        }
        let data = try JSONSerialization.data(withJSONObject: body)
        return try decode(try await transport.send(method: "POST", path: "/v1/models/settings", body: data))
    }

    /// Downloads a model without loading it.
    public func download(_ model: String) async throws -> ModelActionResult {
        try await post("/v1/models/download", ModelActionBody(model: model))
    }

    /// Downloads a model, reporting progress (HTTP only; over a handoff it
    /// reports once, when the download is done).
    public func downloadWithProgress(_ model: String) -> AsyncThrowingStream<DownloadEvent, any Error> {
        let body = try? JSON.encoder.encode(ModelActionBody(model: model, stream: true))
        if let body, let events = transport.events(path: "/v1/models/download", body: body) {
            return events.decoded(as: DownloadEvent.self)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await self.download(model)
                    continuation.yield(DownloadEvent(model: model, status: "downloaded", downloadedBytes: 0, totalBytes: 0))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Downloads if needed and loads into memory. SapientStudio keeps a few
    /// models loaded, releasing the least recently used to make room.
    public func load(_ model: String) async throws -> ModelActionResult {
        try await post("/v1/models/load", ModelActionBody(model: model))
    }

    /// Releases one model's memory, or every model's when `model` is nil.
    public func unload(_ model: String? = nil) async throws -> ModelActionResult {
        try await post("/v1/models/unload", ModelActionBody(model: model))
    }

    /// Deletes a model's downloaded files.
    public func delete(_ model: String) async throws -> ModelActionResult {
        try await post("/v1/models/delete", ModelActionBody(model: model))
    }

    // MARK: Generation

    /// A chat reply. `model` nil uses the most recently used loaded model.
    public func chat(
        _ messages: [Message], model: String? = nil, maxTokens: Int? = nil, stop: [String]? = nil
    ) async throws -> GenerationResult {
        let response: ChatResponseBody = try await post("/v1/chat/completions", ChatRequestBody(
            model: model, messages: messages, stream: false, maxTokens: maxTokens, stop: stop
        ))
        guard let choice = response.choices.first else { throw SapientError.invalidResponse }
        return GenerationResult(
            id: response.id, model: response.model, text: choice.message.content,
            finishReason: choice.finishReason, usage: response.usage
        )
    }

    /// A chat reply as it's generated. Over HTTP each piece arrives as the
    /// model writes it; over a handoff the whole reply arrives at once.
    /// Cancelling the iteration stops generation.
    public func streamChat(
        _ messages: [Message], model: String? = nil, maxTokens: Int? = nil, stop: [String]? = nil
    ) -> AsyncThrowingStream<String, any Error> {
        let body = try? JSON.encoder.encode(ChatRequestBody(
            model: model, messages: messages, stream: true, maxTokens: maxTokens, stop: stop
        ))
        if let body, let events = transport.events(path: "/v1/chat/completions", body: body) {
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        for try await chunk in events.decoded(as: ChatChunkBody.self) {
                            if let text = chunk.choices.first?.delta.content, !text.isEmpty {
                                continuation.yield(text)
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(try await self.chat(messages, model: model, maxTokens: maxTokens, stop: stop).text)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Continues `prompt` (run through the model's chat template on iOS).
    public func complete(
        _ prompt: String, model: String? = nil, maxTokens: Int? = nil, stop: [String]? = nil
    ) async throws -> GenerationResult {
        let response: CompletionResponseBody = try await post("/v1/completions", CompletionRequestBody(
            model: model, prompt: prompt, stream: false, maxTokens: maxTokens, stop: stop
        ))
        guard let choice = response.choices.first else { throw SapientError.invalidResponse }
        return GenerationResult(
            id: response.id, model: response.model, text: choice.text,
            finishReason: choice.finishReason ?? "stop",
            usage: response.usage ?? Usage(promptTokens: 0, completionTokens: 0, totalTokens: 0)
        )
    }

    // MARK: Plumbing

    private func get<Response: Decodable>(_ path: String) async throws -> Response {
        try decode(try await transport.send(method: "GET", path: path, body: nil))
    }

    private func post<Response: Decodable>(_ path: String, _ body: some Encodable) async throws -> Response {
        try decode(try await transport.send(method: "POST", path: path, body: try JSON.encoder.encode(body)))
    }

    private func decode<Response: Decodable>(_ reply: (status: Int, body: Data)) throws -> Response {
        guard reply.status < 400 else { throw Self.apiError(status: reply.status, body: reply.body) }
        do {
            return try JSON.decoder.decode(Response.self, from: reply.body)
        } catch {
            throw SapientError.invalidResponse
        }
    }

    static func apiError(status: Int, body: Data) -> SapientError {
        let message = (try? JSON.decoder.decode(ErrorBody.self, from: body))?.error.message
            ?? String(decoding: body, as: UTF8.self)
        return .api(status: status, message: message)
    }
}

extension AsyncThrowingStream where Element == Data, Failure == any Error {
    func decoded<Value: Decodable & Sendable>(as type: Value.Type) -> AsyncThrowingStream<Value, any Error> {
        AsyncThrowingStream<Value, any Error> { continuation in
            let task = Task {
                do {
                    for try await data in self {
                        continuation.yield(try JSON.decoder.decode(Value.self, from: data))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
