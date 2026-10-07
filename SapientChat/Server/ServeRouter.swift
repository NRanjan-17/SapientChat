import Foundation
import Synchronization

/// `sapient serve`'s HTTP API, answered by the app's own engine. The iOS
/// build of SAPIENT ships without the server, so this mirrors its routes and
/// JSON (crates/sapient-cli/src/server.rs) on top of `chatMessagesStream`,
/// the call serve itself is built on. Models load on demand and share the
/// app's memory slots, so a model loaded over HTTP is the one the app
/// shows in memory, and vice versa.
///
/// Differences from the desktop server, all set by the iOS engine API:
/// - Only catalog models that fit a phone can be loaded.
/// - Usage counts streamed fragments (≈ tokens); `prompt_tokens` is 0.
/// - `temperature` and `tools` aren't applied per request; the engine caps
///   a reply at 512 tokens.
/// - `/v1/completions` runs the prompt through the chat template.
/// - Audio and robot-action routes answer 501.
///
/// SapientChat adds model management that the desktop server doesn't
/// need: `GET /v1/catalog` (filter with `?status=available|downloaded|loaded`),
/// `POST /v1/models/{download,load,unload,delete}` and `GET /v1/ping`, so
/// other apps can see what this device offers and manage it.
final class ServeRouter {
    /// Requests must carry `Authorization: Bearer <apiKey>` when set.
    var apiKey: String?
    /// Each request once its response has fully gone out, for the request log.
    var onRequest: ((RequestLogEntry) -> Void)?
    /// Told each download/load step of a model an API request prepares, then
    /// nil when it's done, so the Models tab shows API work too.
    var onModelPhase: ((String, ModelPhase?) -> Void)?
    /// Shows chat, completion, download and load requests in the Dynamic Island.
    var liveActivities: any LiveActivityService = NoLiveActivities()

    private let services: AppServices
    private let device: DeviceStatus

    init(services: AppServices, device: DeviceStatus) {
        self.services = services
        self.device = device
    }

    /// Answers `request`. `source` names the app that sent it, when known.
    func handle(_ request: HTTPRequest, source: String? = nil) async -> HTTPResponse {
        let activity = Self.showsActivity(request) ? LiveActivityTracker(
            service: liveActivities,
            title: source.map { "Request from \($0)" } ?? "API request"
        ) : nil
        let capture = RequestCapture(request, source: source)
        let response = await route(request, activity: activity, capture: capture)
        switch response.body {
        case .data(let data):
            if let entry = capture.finish(status: response.status, responseBody: data) { onRequest?(entry) }
            return response
        case .stream(let chunks):
            // Logged when the stream ends, so a streamed reply is saved complete.
            let status = response.status
            let report = onRequest
            let (relayed, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
            let task = Task {
                do {
                    for try await chunk in chunks { continuation.yield(chunk) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                if let entry = capture.finish(status: status, responseBody: nil) { report?(entry) }
            }
            continuation.onTermination = { _ in task.cancel() }
            return HTTPResponse(status: status, contentType: response.contentType, body: .stream(relayed))
        }
    }

    /// Requests that do model work worth showing in the Dynamic Island.
    private static func showsActivity(_ request: HTTPRequest) -> Bool {
        request.method == "POST" && [
            "/v1/chat/completions", "/v1/completions", "/v1/models/download", "/v1/models/load",
        ].contains(request.path)
    }

    private func route(_ request: HTTPRequest, activity: LiveActivityTracker?, capture: RequestCapture) async -> HTTPResponse {
        if request.method == "OPTIONS" {
            return .empty(status: 204)
        }
        if let apiKey, !apiKey.isEmpty, request.header("Authorization") != "Bearer \(apiKey)" {
            return .json(ServeErrorBody(error: .init(message: "Invalid API key", type: "authentication_error")), status: 401)
        }
        switch (request.method, request.path) {
        case ("GET", "/v1/models"):
            return await models()
        case ("GET", "/v1/health"):
            return await health()
        case ("GET", "/v1/ping"):
            return .json(PingResponse(version: SapientVersion.current))
        case ("POST", "/v1/chat/completions"):
            return await chatCompletions(request, activity: activity, capture: capture)
        case ("POST", "/v1/completions"):
            return await completions(request, activity: activity, capture: capture)
        case ("GET", "/v1/catalog"):
            return await catalog(request)
        case ("POST", "/v1/models/download"):
            return await download(request, activity: activity, capture: capture)
        case ("POST", "/v1/models/load"):
            return await load(request, activity: activity, capture: capture)
        case ("POST", "/v1/models/unload"):
            return await unload(request)
        case ("POST", "/v1/models/delete"):
            return await deleteDownload(request)
        case ("POST", "/v1/audio/transcriptions"), ("POST", "/v1/audio/speech"), ("POST", "/v1/actions"):
            return .json(ServeErrorBody.server("\(request.path) isn't available in SAPIENT's iOS engine"), status: 501)
        case (_, let path) where Self.routes.contains(path):
            return .json(ServeErrorBody.invalidRequest("Method \(request.method) not allowed on \(path)"), status: 405)
        default:
            return .json(ServeErrorBody.invalidRequest("No route for \(request.path)"), status: 404)
        }
    }

    // MARK: Routes

    private func models() async -> HTTPResponse {
        let created = Int(Date.now.timeIntervalSince1970)
        let resident = await services.chat.loadedModels()
        let downloaded = services.catalog.chatModels().filter { services.storage.download(forRepo: $0.repoId).isDownloaded }
        return .json(ModelList(
            data: downloaded.map { ModelList.Model(id: $0.alias, created: created) },
            activeModel: resident.first,
            residentModels: resident
        ))
    }

    private func health() async -> HTTPResponse {
        let resident = await services.chat.loadedModels()
        device.refreshMemory()
        return .json(HealthResponse(
            version: SapientVersion.current, loadedModel: resident.first, residentModels: resident,
            maxResidentModels: LoadedSlots<Void>.defaultCapacity,
            device: DeviceHealth(
                footprintBytes: device.memory.footprintBytes,
                availableBytes: device.memory.availableBytes,
                thermal: String(describing: device.thermal)
            )
        ))
    }

    // MARK: Model management

    /// Which models `GET /v1/catalog` lists.
    enum CatalogFilter: String, CaseIterable, Sendable {
        /// Not on this device yet (including partly downloaded ones).
        case available
        case downloaded
        /// In memory now.
        case loaded

        func includes(_ model: CatalogResponse.Model) -> Bool {
            switch self {
            case .available: !model.downloaded
            case .downloaded: model.downloaded
            case .loaded: model.loaded
            }
        }
    }

    private func catalog(_ request: HTTPRequest) async -> HTTPResponse {
        var filter: CatalogFilter?
        if let status = request.query["status"], !status.isEmpty {
            guard let parsed = CatalogFilter(rawValue: status) else {
                let allowed = CatalogFilter.allCases.map(\.rawValue).joined(separator: ", ")
                return .json(ServeErrorBody.invalidRequest("Unknown status '\(status)'. Use one of: \(allowed)."), status: 400)
            }
            filter = parsed
        }
        let resident = await services.chat.loadedModels()
        device.refreshMemory()
        let catalog = services.catalog.chatModels()
        let loaded = resident.map { alias in (alias: alias, model: catalog.first { $0.alias == alias }) }
        let models = catalog.map { model in
            let download = services.storage.download(forRepo: model.repoId)
            return CatalogResponse.Model(
                id: model.alias, name: model.displayName, params: model.params, format: model.format,
                parameterBillions: model.billions, estimatedMemoryBytes: model.estimatedMemoryBytes,
                downloaded: download.isDownloaded, downloadedBytes: download.bytes,
                loaded: resident.contains(model.alias),
                fits: MemoryPlanner.plan(loading: model, loaded: loaded, availableBytes: device.memory.availableBytes).fits,
                memory: Format.bytes(model.estimatedMemoryBytes),
                sizeOnDisk: Format.bytes(download.bytes)
            )
        }
        return .json(CatalogResponse(
            data: filter.map { filter in models.filter(filter.includes) } ?? models,
            residentModels: resident,
            maxResidentModels: LoadedSlots<Void>.defaultCapacity
        ))
    }

    /// Downloads without loading. With `stream`, sends progress events.
    private func download(_ request: HTTPRequest, activity: LiveActivityTracker?, capture: RequestCapture) async -> HTTPResponse {
        let model: PhoneModel
        switch requiredModel(request) {
        case .success(let found): model = found
        case .failure(let failure): return failure.response
        }
        activity?.start(model: model.displayName)
        capture.model(model.alias)
        let stream = (try? APIJSON.decoder.decode(ModelActionRequest.self, from: request.body))?.stream ?? false
        let downloads = services.downloads
        let alias = model.alias
        guard stream else {
            defer { onModelPhase?(alias, nil) }
            do {
                try await ModelPreparer(services: services, device: device).download(alias) { phase in
                    activity?.phase(phase)
                    onModelPhase?(alias, phase)
                }
                activity?.finish(detail: "Downloaded")
                return .json(ModelActionResponse(model: alias, status: "downloaded", residentModels: await services.chat.loadedModels()))
            } catch {
                activity?.fail(Self.describe(error))
                return .json(ServeErrorBody.server(Self.describe(error)), status: 500)
            }
        }
        let (events, continuation) = AsyncThrowingStream<DownloadEvent, any Error>.makeStream()
        let reportPhase = onModelPhase
        let task = Task {
            do {
                // Progress arrives on the engine's thread.
                let latest = Mutex(DownloadProgress.starting)
                try await downloads.download(model: alias) { progress in
                    latest.withLock { $0 = progress }
                    Task { @MainActor in
                        activity?.phase(.downloading(progress))
                        reportPhase?(alias, .downloading(progress))
                    }
                    continuation.yield(DownloadEvent(
                        model: alias, status: "downloading",
                        downloadedBytes: progress.downloadedBytes, totalBytes: progress.totalBytes
                    ))
                }
                let last = latest.withLock { $0 }
                continuation.yield(DownloadEvent(
                    model: alias, status: "downloaded",
                    downloadedBytes: max(last.downloadedBytes, last.totalBytes), totalBytes: last.totalBytes
                ))
                continuation.finish()
                activity?.finish(detail: "Downloaded")
            } catch {
                activity?.fail(Self.describe(error))
                continuation.finish(throwing: error)
            }
            // After the last progress hop, so the row doesn't reappear.
            Task { @MainActor in reportPhase?(alias, nil) }
        }
        continuation.onTermination = { _ in task.cancel() }
        return eventStream(events) { event in
            event.status == "downloaded" ? APIJSON.event(event) + Self.done : APIJSON.event(event)
        }
    }

    /// Downloads if needed, then loads into a memory slot.
    private func load(_ request: HTTPRequest, activity: LiveActivityTracker?, capture: RequestCapture) async -> HTTPResponse {
        let found: PhoneModel
        switch requiredModel(request) {
        case .success(let model): found = model
        case .failure(let failure): return failure.response
        }
        switch await prepare(found.alias, activity: activity, capture: capture) {
        case .success(let (model, backend)):
            activity?.finish(detail: "Loaded · \(backend)")
            return .json(ModelActionResponse(
                model: model.alias, status: "loaded", backend: backend, residentModels: await services.chat.loadedModels()
            ))
        case .failure(let failure):
            return failure.response
        }
    }

    /// Releases one model, or every model when none is named.
    private func unload(_ request: HTTPRequest) async -> HTTPResponse {
        switch modelAction(request) {
        case .success(let (model, _)):
            if let model {
                await services.chat.unload(model: model.alias)
            } else {
                await services.chat.unloadAll()
            }
            device.refreshMemory()
            return .json(ModelActionResponse(model: model?.alias, status: "unloaded", residentModels: await services.chat.loadedModels()))
        case .failure(let failure):
            return failure.response
        }
    }

    /// Deletes a model's files (unloading it first).
    private func deleteDownload(_ request: HTTPRequest) async -> HTTPResponse {
        let model: PhoneModel
        switch requiredModel(request) {
        case .success(let found): model = found
        case .failure(let failure): return failure.response
        }
        await services.chat.unload(model: model.alias)
        do {
            try services.storage.deleteDownload(forRepo: model.repoId)
        } catch {
            return .json(ServeErrorBody.server(Self.describe(error)), status: 500)
        }
        device.refreshMemory()
        return .json(ModelActionResponse(model: model.alias, status: "deleted", residentModels: await services.chat.loadedModels()))
    }

    /// The model a download, load or delete names; it must name one.
    private func requiredModel(_ request: HTTPRequest) -> Result<PhoneModel, Failure> {
        switch modelAction(request) {
        case .success(let (model?, _)): .success(model)
        case .success: .failure(Failure(response: .json(ServeErrorBody.invalidRequest("'model' is required"), status: 400)))
        case .failure(let failure): .failure(failure)
        }
    }

    /// The body of a model action, and its model resolved (nil if omitted).
    private func modelAction(_ request: HTTPRequest) -> Result<(PhoneModel?, ModelActionRequest), Failure> {
        let body: ModelActionRequest
        if request.body.isEmpty {
            body = ModelActionRequest()
        } else {
            guard let decoded = try? APIJSON.decoder.decode(ModelActionRequest.self, from: request.body) else {
                return .failure(Failure(response: .json(ServeErrorBody.invalidRequest("Invalid request body"), status: 422)))
            }
            body = decoded
        }
        guard let name = body.model, !name.isEmpty else { return .success((nil, body)) }
        guard let model = resolve(name) else {
            return .failure(Failure(response: .json(ServeErrorBody.modelNotFound(
                "Model '\(name)' isn't in this device's catalog. GET /v1/catalog lists them."
            ), status: 400)))
        }
        return .success((model, body))
    }

    private func chatCompletions(_ request: HTTPRequest, activity: LiveActivityTracker?, capture: RequestCapture) async -> HTTPResponse {
        let body: ChatCompletionRequest
        do {
            body = try APIJSON.decoder.decode(ChatCompletionRequest.self, from: request.body)
        } catch {
            return .json(ServeErrorBody.invalidRequest("Invalid request body: \(error.localizedDescription)"), status: 422)
        }
        if body.tools?.isEmpty == false {
            return .json(ServeErrorBody.modelNotFound("Tools aren't supported by SAPIENT's iOS engine; send the request without tools."), status: 400)
        }
        guard let history = Self.history(body.messages), !history.isEmpty else {
            return .json(ServeErrorBody.invalidRequest("messages must be non-empty and use the system, user or assistant roles"), status: 400)
        }
        let model: PhoneModel
        switch await prepare(body.model, activity: activity, capture: capture) {
        case .success(let ready): model = ready.model
        case .failure(let failure): return failure.response
        }
        let events = generation(
            model: model, history: history, limit: body.maxTokens, stops: body.stop?.values ?? [], activity: activity, capture: capture
        )
        let id = Self.newID()
        let created = Int(Date.now.timeIntervalSince1970)

        guard body.stream ?? false else {
            do {
                let (text, usage) = try await Self.collect(events)
                return .json(ChatCompletionResponse(
                    id: id, created: created, model: model.alias,
                    choices: [.init(index: 0, message: ServeMessage(role: "assistant", content: text), finishReason: "stop")],
                    usage: usage
                ))
            } catch {
                return .json(ServeErrorBody.server(Self.describe(error)), status: 500)
            }
        }

        func chunk(_ delta: ChatCompletionChunk.Delta, finish: String? = nil, usage: Usage? = nil) -> Data {
            APIJSON.event(ChatCompletionChunk(
                id: id, created: created, model: model.alias,
                choices: [.init(index: 0, delta: delta, finishReason: finish)], usage: usage
            ))
        }
        // Like serve: the role first, then content, then a final chunk with
        // the finish reason and usage, then [DONE].
        return eventStream(events, first: chunk(.init(role: "assistant"))) { event in
            switch event {
            case .text(let text): chunk(.init(content: text))
            case .done(let usage): chunk(.init(), finish: "stop", usage: usage) + Self.done
            }
        }
    }

    private func completions(_ request: HTTPRequest, activity: LiveActivityTracker?, capture: RequestCapture) async -> HTTPResponse {
        let body: CompletionRequest
        do {
            body = try APIJSON.decoder.decode(CompletionRequest.self, from: request.body)
        } catch {
            return .json(ServeErrorBody.invalidRequest("Invalid request body: \(error.localizedDescription)"), status: 422)
        }
        let model: PhoneModel
        switch await prepare(body.model, activity: activity, capture: capture) {
        case .success(let ready): model = ready.model
        case .failure(let failure): return failure.response
        }
        let events = generation(
            model: model, history: [ChatMessage(role: .user, text: body.prompt)],
            limit: body.maxTokens, stops: body.stop?.values ?? [], activity: activity, capture: capture
        )
        let id = Self.newID()
        let created = Int(Date.now.timeIntervalSince1970)

        guard body.stream ?? false else {
            do {
                let (text, usage) = try await Self.collect(events)
                return .json(CompletionResponse(
                    id: id, created: created, model: model.alias,
                    choices: [.init(index: 0, text: text, finishReason: "stop")], usage: usage
                ))
            } catch {
                return .json(ServeErrorBody.server(Self.describe(error)), status: 500)
            }
        }
        return eventStream(events) { event in
            let (text, finish, usage): (String, String?, Usage?) = switch event {
            case .text(let text): (text, nil, nil)
            case .done(let usage): ("", "stop", usage)
            }
            let data = APIJSON.event(CompletionResponse(
                id: id, created: created, model: model.alias,
                choices: [.init(index: 0, text: text, finishReason: finish)], usage: usage
            ))
            return usage == nil ? data : data + Self.done
        }
    }

    // MARK: Generation

    enum GenerationEvent: Sendable {
        case text(String)
        case done(Usage)
    }

    /// Streams `model`'s reply, then `.done` with usage. Ends early after
    /// `limit` fragments or at a stop sequence; cancelling the consumer
    /// (the client hanging up) stops the engine.
    private func generation(
        model: PhoneModel, history: [ChatMessage], limit: Int?, stops: [String],
        activity: LiveActivityTracker?, capture: RequestCapture
    ) -> AsyncThrowingStream<GenerationEvent, any Error> {
        let chat = services.chat
        let (events, continuation) = AsyncThrowingStream<GenerationEvent, any Error>.makeStream()
        let task = Task {
            var filter = StopSequenceFilter(stops)
            var count = 0
            activity?.generating()
            capture.prompt(history)
            capture.generating()
            do {
                for try await fragment in try await chat.reply(to: history, model: model.alias) {
                    count += 1
                    activity?.token()
                    let text = filter.feed(fragment)
                    capture.token(text)
                    if !text.isEmpty { continuation.yield(.text(text)) }
                    if filter.isStopped { break }
                    if let limit, limit > 0, count >= limit { break }
                }
                let rest = filter.flush()
                capture.append(rest)
                if !rest.isEmpty { continuation.yield(.text(rest)) }
                continuation.yield(.done(Usage(promptTokens: 0, completionTokens: count, totalTokens: count)))
                continuation.finish()
                activity?.finish()
            } catch is CancellationError {
                activity?.finish(detail: "Stopped")
                capture.failed("Stopped: the client disconnected")
                continuation.finish(throwing: CancellationError())
            } catch {
                activity?.fail(Self.describe(error))
                capture.failed(Self.describe(error))
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
        return events
    }

    /// A server-sent event stream framing each event as it arrives. A
    /// failure mid-stream is sent as an error event, since the status line
    /// is already out.
    private func eventStream<Event>(
        _ events: AsyncThrowingStream<Event, any Error>,
        first: Data? = nil,
        frame: @escaping (Event) -> Data
    ) -> HTTPResponse {
        let (stream, continuation) = AsyncThrowingStream<Data, any Error>.makeStream()
        if let first { continuation.yield(first) }
        let task = Task {
            do {
                for try await event in events { continuation.yield(frame(event)) }
            } catch is CancellationError {
            } catch {
                continuation.yield(APIJSON.event(ServeErrorBody.server(Self.describe(error))))
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in task.cancel() }
        return HTTPResponse(status: 200, contentType: "text/event-stream", body: .stream(stream))
    }

    private static func collect(_ events: AsyncThrowingStream<GenerationEvent, any Error>) async throws -> (String, Usage) {
        var text = ""
        var usage = Usage(promptTokens: 0, completionTokens: 0, totalTokens: 0)
        for try await event in events {
            switch event {
            case .text(let fragment): text += fragment
            case .done(let final): usage = final
            }
        }
        return (text, usage)
    }

    // MARK: Models

    private struct Failure: Error {
        let response: HTTPResponse
    }

    /// Picks the model like serve (the requested one, else the most
    /// recently used loaded one), then downloads it if needed and loads it,
    /// releasing least recently used models to make room as the app does.
    private func prepare(
        _ requested: String?, activity: LiveActivityTracker? = nil, capture: RequestCapture? = nil
    ) async -> Result<(model: PhoneModel, backend: String), Failure> {
        let name: String
        if let requested, !requested.isEmpty {
            name = requested
        } else if let active = await services.chat.loadedModels().first {
            name = active
        } else {
            return .failure(Failure(response: .json(ServeErrorBody.modelNotFound(
                "No model specified and no model is currently loaded. Pass 'model' in the request, or load one in the app."
            ), status: 400)))
        }
        guard let model = resolve(name) else {
            return .failure(Failure(response: .json(ServeErrorBody.modelNotFound(
                "Model '\(name)' isn't available on this device. GET /v1/models lists downloaded models."
            ), status: 400)))
        }
        activity?.start(model: model.displayName)
        capture?.model(model.alias)
        let alias = model.alias
        defer { onModelPhase?(alias, nil) }
        do {
            let backend = try await ModelPreparer(services: services, device: device).prepare(alias) { phase in
                activity?.phase(phase)
                onModelPhase?(alias, phase)
            }
            return .success((model, backend))
        } catch ChatViewModelError.wontFit(let message) {
            activity?.fail(message)
            return .failure(Failure(response: .json(ServeErrorBody.server(message), status: 500)))
        } catch {
            activity?.fail(Self.describe(error))
            return .failure(Failure(response: .json(ServeErrorBody.server(Self.describe(error)), status: 500)))
        }
    }

    /// Releases every model, e.g. so they reload on a different backend.
    func releaseAllModels() async {
        await services.chat.unloadAll()
    }

    /// Every model this device's catalog offers.
    func catalogModels() -> [PhoneModel] {
        services.catalog.chatModels()
    }

    /// A catalog model by alias, or by name without the `openhorizon/` prefix.
    func resolve(_ name: String) -> PhoneModel? {
        services.catalog.chatModels().first { $0.alias == name || $0.displayName == name }
    }

    // MARK: Helpers

    private static let routes: Set<String> = [
        "/v1/models", "/v1/health", "/v1/ping", "/v1/chat/completions", "/v1/completions",
        "/v1/catalog", "/v1/models/download", "/v1/models/load", "/v1/models/unload", "/v1/models/delete",
        "/v1/audio/transcriptions", "/v1/audio/speech", "/v1/actions",
    ]

    private static let done = Data("data: [DONE]\n\n".utf8)

    /// Client messages as chat history; nil if a role isn't supported.
    static func history(_ messages: [ServeMessage]) -> [ChatMessage]? {
        var history: [ChatMessage] = []
        for message in messages {
            guard let role = ChatMessage.Role(rawValue: message.role) else { return nil }
            history.append(ChatMessage(role: role, text: message.content))
        }
        return history
    }

    private static func newID() -> String {
        "chatcmpl-" + UUID().uuidString.replacing("-", with: "").lowercased().prefix(24)
    }

    /// SapientError isn't a LocalizedError; its description carries the reason.
    private static func describe(_ error: any Error) -> String {
        (error as? any LocalizedError)?.errorDescription ?? String(describing: error)
    }
}
