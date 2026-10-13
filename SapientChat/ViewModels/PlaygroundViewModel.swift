// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// The Playground: build an API request, run it against the app's own
/// router (the one the server and URL handoffs use, so nothing here can
/// differ from what a client gets), and read the reply, the raw response
/// and the timing. Requests show up in the request log like any other.
@Observable
final class PlaygroundViewModel {
    struct Draft: Identifiable, Equatable {
        let id = UUID()
        var role: String
        var text: String
    }

    struct Metrics: Equatable {
        var status: Int
        var durationMs: Int
        var firstTokenMs: Int?
        var tokens: Int?
        var tokensPerSecond: Double?
    }

    enum Snippet: String, CaseIterable, Identifiable {
        case curl = "curl"
        case python = "Python"
        case swift = "Swift"

        var id: String { rawValue }
    }

    static let chatPath = "/v1/chat/completions"
    static let roles = ["user", "assistant", "system"]
    /// 0 is no limit: the reply ends when the model does.
    static let maxTokenChoices = [0, 64, 128, 256, 512, 1024, 2048]

    // MARK: Request

    var model: String
    var systemPrompt = ""
    var messages = [Draft(role: "user", text: "")]
    var maxTokens = 0
    /// Stop sequences, one per line.
    var stopText = ""
    var streams = true
    /// Ask for a JSON reply (`response_format`).
    var wantsJSON = false
    /// Tool definitions as a JSON array; empty for none.
    var toolsText = ""
    /// Send `rawBody` as typed instead of the form's fields.
    var isRaw = false
    var method = "POST"
    var path = PlaygroundViewModel.chatPath
    var rawBody = ""

    // MARK: Response

    private(set) var isRunning = false
    /// The reply's text as it streams in.
    private(set) var reply = ""
    private(set) var rawResponse = ""
    private(set) var metrics: Metrics?
    private(set) var errorMessage: String?
    /// A caution about the reply, e.g. JSON was asked for and didn't come back.
    private(set) var notice: String?

    @ObservationIgnored private let router: ServeRouter
    /// Where a client on another device reaches the server.
    @ObservationIgnored private let baseURL: () -> String
    @ObservationIgnored private var task: Task<Void, Never>?

    init(router: ServeRouter, model: String, baseURL: @escaping () -> String) {
        self.router = router
        self.model = model
        self.baseURL = baseURL
    }

    var canRun: Bool {
        guard !isRunning else { return false }
        if isRaw { return !path.isEmpty }
        return messages.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } && toolsProblem == nil
    }

    /// Why the tools text can't be sent, or nil.
    var toolsProblem: String? {
        let text = toolsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return "Tools isn't valid JSON." }
        return value is [Any] ? nil : "Tools must be a JSON array."
    }

    /// Everything the model will read, for the token estimate.
    var promptText: String {
        if isRaw { return rawBody }
        return ([systemPrompt] + messages.map(\.text) + [toolsText]).joined(separator: "\n")
    }

    // MARK: Building the request

    /// The form as a request body, keys in the order a person reads them.
    var formObject: [String: Any] {
        var body: [String: Any] = ["model": model]
        var list: [[String: Any]] = []
        let system = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty { list.append(["role": "system", "content": system]) }
        for message in messages where !message.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            list.append(["role": message.role, "content": message.text])
        }
        body["messages"] = list
        body["stream"] = streams
        if maxTokens > 0 { body["max_tokens"] = maxTokens }
        let stops = stopText.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        if !stops.isEmpty { body["stop"] = stops }
        if wantsJSON { body["response_format"] = ["type": "json_object"] }
        let tools = toolsText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tools.isEmpty, let value = try? JSONSerialization.jsonObject(with: Data(tools.utf8)) as? [Any] {
            body["tools"] = value
        }
        return body
    }

    /// The body that Run sends, pretty-printed.
    var requestBodyText: String {
        isRaw ? rawBody : Self.json(formObject, pretty: true)
    }

    static func json(_ object: Any, pretty: Bool) -> String {
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        if pretty { options.insert(.prettyPrinted) }
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: options)
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Switches to the raw editor, starting from what the form would send.
    func editAsJSON() {
        rawBody = Self.json(formObject, pretty: true)
        isRaw = true
    }

    /// Opens a request as sent before (from the request log), ready to
    /// change and run again. A chat request the form can show goes into the
    /// form; anything else into the raw editor.
    func open(method: String, path: String, body: String?) {
        cancel()
        clearResponse()
        self.method = method
        self.path = path
        rawBody = body ?? ""
        isRaw = !(path == Self.chatPath && method == "POST" && fillForm(from: rawBody))
    }

    /// Fills the form from a chat request body; false when it has fields
    /// the form can't show, so nothing is silently dropped.
    private func fillForm(from body: String) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any],
              let list = object["messages"] as? [[String: Any]]
        else { return false }
        let known: Set = ["model", "messages", "stream", "max_tokens", "stop", "response_format", "tools"]
        guard Set(object.keys).isSubset(of: known) else { return false }
        var system = ""
        var drafts: [Draft] = []
        for item in list {
            guard let role = item["role"] as? String, let content = item["content"] as? String, Self.roles.contains(role),
                  item.count == 2
            else { return false }
            if role == "system", drafts.isEmpty, system.isEmpty {
                system = content
            } else {
                drafts.append(Draft(role: role, text: content))
            }
        }
        if let name = object["model"] as? String, let known = router.resolve(name) { model = known.alias }
        systemPrompt = system
        messages = drafts.isEmpty ? [Draft(role: "user", text: "")] : drafts
        streams = object["stream"] as? Bool ?? false
        maxTokens = object["max_tokens"] as? Int ?? 0
        stopText = ((object["stop"] as? [String]) ?? (object["stop"] as? String).map { [$0] } ?? []).joined(separator: "\n")
        wantsJSON = ((object["response_format"] as? [String: Any])?["type"] as? String).map { $0 != "text" } ?? false
        toolsText = (object["tools"] as? [Any]).map { Self.json($0, pretty: true) } ?? ""
        return true
    }

    func addMessage() {
        let next = messages.last?.role == "user" ? "assistant" : "user"
        messages.append(Draft(role: next, text: ""))
    }

    func remove(_ draft: Draft) {
        messages.removeAll { $0.id == draft.id }
        if messages.isEmpty { messages = [Draft(role: "user", text: "")] }
    }

    /// Back to an empty chat request.
    func reset() {
        cancel()
        clearResponse()
        systemPrompt = ""
        messages = [Draft(role: "user", text: "")]
        maxTokens = 0
        stopText = ""
        streams = true
        wantsJSON = false
        toolsText = ""
        isRaw = false
        method = "POST"
        path = Self.chatPath
        rawBody = ""
    }

    // MARK: Running

    func run() {
        guard canRun else { return }
        clearResponse()
        isRunning = true
        var request = HTTPRequest(method: isRaw ? method : "POST", path: isRaw ? path : Self.chatPath)
        request.headers["content-type"] = "application/json"
        if let key = router.apiKey, !key.isEmpty { request.headers["authorization"] = "Bearer \(key)" }
        request.body = Data(requestBodyText.utf8)
        task = Task { [weak self] in await self?.send(request) }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    private func clearResponse() {
        reply = ""
        rawResponse = ""
        metrics = nil
        errorMessage = nil
        notice = nil
    }

    private func send(_ request: HTTPRequest) async {
        let started = ContinuousClock.now
        var firstToken: ContinuousClock.Instant?
        var lastToken: ContinuousClock.Instant?
        var fragments = 0
        var reportedTokens: Int?
        let response = await router.handle(request, source: "Playground")
        do {
            switch response.body {
            case .data(let data):
                rawResponse = String(decoding: data, as: UTF8.self)
                let parsed = Self.parse(json: data)
                reply = parsed.text
                errorMessage = parsed.error
                reportedTokens = parsed.tokens
                notice = Self.notice(in: data)
            case .stream(let chunks):
                var pending = Data()
                let separator = Data("\n\n".utf8)
                for try await chunk in chunks {
                    pending.append(chunk)
                    while let end = pending.firstRange(of: separator) {
                        let event = String(decoding: pending[pending.startIndex..<end.lowerBound], as: UTF8.self)
                        pending.removeSubrange(pending.startIndex..<end.upperBound)
                        rawResponse += event + "\n\n"
                        guard event.hasPrefix("data: "), event != "data: [DONE]" else { continue }
                        let parsed = Self.parse(json: Data(event.dropFirst(6).utf8))
                        if !parsed.text.isEmpty {
                            let now = ContinuousClock.now
                            if firstToken == nil { firstToken = now }
                            lastToken = now
                            fragments += 1
                            reply += parsed.text
                        }
                        if let error = parsed.error { errorMessage = error }
                        if let caution = Self.notice(in: Data(event.dropFirst(6).utf8)) { notice = caution }
                        if let tokens = parsed.tokens { reportedTokens = tokens }
                    }
                }
            }
        } catch {
            if !(error is CancellationError) { errorMessage = error.localizedDescription }
        }
        guard !Task.isCancelled else { return }
        var result = Metrics(status: response.status, durationMs: (ContinuousClock.now - started).milliseconds)
        result.firstTokenMs = firstToken.map { ($0 - started).milliseconds }
        result.tokens = reportedTokens ?? (fragments > 0 ? fragments : nil)
        if let firstToken, let lastToken, fragments > 1 {
            let seconds = Double((lastToken - firstToken).milliseconds) / 1000
            if seconds > 0 { result.tokensPerSecond = Double(fragments - 1) / seconds }
        }
        metrics = result
        isRunning = false
        task = nil
    }

    /// The text, error and token count in one response object or stream
    /// event, whichever of the API's shapes it has.
    static func parse(json data: Data) -> (text: String, error: String?, tokens: Int?) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ("", nil, nil) }
        let error = (object["error"] as? [String: Any])?["message"] as? String
        let tokens = (object["usage"] as? [String: Any])?["completion_tokens"] as? Int
        guard let choice = (object["choices"] as? [[String: Any]])?.first else { return ("", error, tokens) }
        let message = (choice["delta"] as? [String: Any]) ?? (choice["message"] as? [String: Any])
        var text = (message?["content"] as? String) ?? (choice["text"] as? String) ?? ""
        // A tool call has no text; show the call itself.
        if text.isEmpty, let calls = message?["tool_calls"] as? [Any], !calls.isEmpty {
            text = json(calls, pretty: true)
        }
        return (text, error, tokens)
    }

    /// What the response's `sapient` note says went wrong, if anything.
    static func notice(in data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let note = object["sapient"] as? [String: Any]
        else { return nil }
        if note["json_valid"] as? Bool == false {
            return "JSON was asked for, but the model's reply isn't valid JSON. It's shown as written."
        }
        if let missing = note["missing_keys"] as? [String], !missing.isEmpty {
            return "The JSON is valid but lacks required keys: \(missing.joined(separator: ", "))."
        }
        return nil
    }

    // MARK: Code

    /// The request as code that runs from another device. It needs the
    /// server on (Settings → API Server).
    func code(_ snippet: Snippet) -> String {
        let url = baseURL() + (isRaw ? path : Self.chatPath)
        let verb = isRaw ? method : "POST"
        let object = try? JSONSerialization.jsonObject(with: Data(requestBodyText.utf8))
        let body = object.map { Self.json($0, pretty: false) } ?? requestBodyText
        let key = router.apiKey.flatMap { $0.isEmpty ? nil : $0 }
        let hasBody = verb != "GET" && !body.isEmpty
        switch snippet {
        case .curl:
            var parts = ["curl \(streams && !isRaw ? "-N " : "")-X \(verb) '\(url)'"]
            if hasBody { parts.append("-H 'Content-Type: application/json'") }
            if let key { parts.append("-H 'Authorization: Bearer \(key)'") }
            if hasBody { parts.append("-d '\(body.replacing("'", with: "'\\''"))'") }
            return parts.joined(separator: " \\\n  ")
        case .python:
            var lines = ["import requests", ""]
            var headers = hasBody ? ["\"Content-Type\": \"application/json\""] : []
            if let key { headers.append("\"Authorization\": \"Bearer \(key)\"") }
            lines.append("response = requests.request(")
            lines.append("    \"\(verb)\", \"\(url)\",")
            lines.append("    headers={\(headers.joined(separator: ", "))},")
            if hasBody { lines.append("    data=r'''\(body)'''.encode(),") }
            lines.append(")")
            lines.append("print(response.text)")
            return lines.joined(separator: "\n")
        case .swift:
            var lines = ["import Foundation", "", "var request = URLRequest(url: URL(string: \"\(url)\")!)", "request.httpMethod = \"\(verb)\""]
            if hasBody { lines.append("request.setValue(\"application/json\", forHTTPHeaderField: \"Content-Type\")") }
            if let key { lines.append("request.setValue(\"Bearer \(key)\", forHTTPHeaderField: \"Authorization\")") }
            if hasBody { lines.append("request.httpBody = Data(#\"\"\"\n\(body)\n\"\"\"#.utf8)") }
            lines.append("let (data, _) = try await URLSession.shared.data(for: request)")
            lines.append("print(String(decoding: data, as: UTF8.self))")
            return lines.joined(separator: "\n")
        }
    }
}
