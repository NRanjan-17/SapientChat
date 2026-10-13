// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Tool calling and JSON replies for `/v1/chat/completions`.
///
/// The engine can't constrain what a model writes, so both are done around
/// it: the request's tools or format become instructions in the system
/// message, and the reply is read back for a tool call or a JSON value.
/// That makes them best effort. A model that ignores the instructions gets
/// its text returned as an ordinary reply, and the response says so
/// (`sapient.json_valid`), so a client never mistakes prose for JSON.
///
/// The request body is read with `JSONSerialization`, not `Codable`: the
/// API's decoder renames snake_case keys, which would change the property
/// names inside a tool's parameter schema.
nonisolated struct StructuredOutput: Sendable {
    enum ToolChoice: Equatable, Sendable {
        /// The model decides.
        case auto
        /// Tools are ignored for this request.
        case none
        /// The model must call some tool.
        case required
        /// The model must call this tool.
        case function(String)
    }

    enum Format: Equatable, Sendable {
        case text
        case jsonObject
        /// `schema` as JSON text; `required` are its top-level required keys.
        case jsonSchema(schema: String, required: [String])
    }

    /// What a reply turned out to be.
    enum Outcome: Equatable, Sendable {
        case toolCalls([ToolCall])
        /// `jsonValid` is nil when no JSON was asked for; `missingKeys` are
        /// required schema keys the object lacks.
        case content(String, jsonValid: Bool?, missingKeys: [String])
    }

    static let openTag = "<tool_call>"
    static let closeTag = "</tool_call>"

    /// The tools as the model is shown them: `[{"name", "description", "parameters"}]`.
    let toolsJSON: String
    let toolNames: [String]
    let toolChoice: ToolChoice
    let format: Format

    /// Whether the request offers tools the model may call.
    var usesTools: Bool { !toolNames.isEmpty && toolChoice != .none }

    /// Whether the reply has to be read back before it's sent, so it can't
    /// be streamed token by token.
    var isActive: Bool { usesTools || format != .text }

    /// Reads `tools`, `tool_choice` and `response_format` from a request body.
    init(body: Data) {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        var specs: [[String: Any]] = []
        var names: [String] = []
        for tool in object["tools"] as? [[String: Any]] ?? [] {
            // OpenAI nests the function; some clients send it flat.
            let function = tool["function"] as? [String: Any] ?? tool
            guard let name = function["name"] as? String, !name.isEmpty else { continue }
            var spec: [String: Any] = ["name": name]
            if let description = function["description"] as? String { spec["description"] = description }
            if let parameters = function["parameters"] as? [String: Any] { spec["parameters"] = parameters }
            specs.append(spec)
            names.append(name)
        }
        toolNames = names
        toolsJSON = Self.text(of: specs) ?? "[]"

        if let choice = object["tool_choice"] as? String {
            toolChoice = switch choice {
            case "none": .none
            case "required": .required
            default: .auto
            }
        } else if let choice = object["tool_choice"] as? [String: Any],
                  let name = (choice["function"] as? [String: Any])?["name"] as? String ?? choice["name"] as? String {
            toolChoice = .function(name)
        } else {
            toolChoice = .auto
        }

        let wanted = object["response_format"] as? [String: Any]
        switch wanted?["type"] as? String {
        case "json_object":
            format = .jsonObject
        case "json_schema":
            let wrapper = wanted?["json_schema"] as? [String: Any]
            let schema = wrapper?["schema"] as? [String: Any] ?? wrapper ?? [:]
            format = .jsonSchema(schema: Self.text(of: schema) ?? "{}", required: schema["required"] as? [String] ?? [])
        default:
            format = .text
        }
    }

    // MARK: Prompt

    /// What the system message is given so the model knows the tools and
    /// the format; nil when the request asks for neither.
    var instructions: String? {
        var parts: [String] = []
        if usesTools {
            var text = "You can call tools. Available tools, as JSON:\n\(toolsJSON)\n\n"
                + "To call a tool, reply with only this line and nothing else:\n"
                + "\(Self.openTag){\"name\": \"<tool name>\", \"arguments\": {<arguments as JSON>}}\(Self.closeTag)\n"
            switch toolChoice {
            case .required: text += "You must call one of the tools."
            case .function(let name): text += "You must call the tool \"\(name)\"."
            case .auto, .none: text += "If no tool is needed, answer normally without the tag."
            }
            parts.append(text)
        }
        switch format {
        case .text:
            break
        case .jsonObject:
            parts.append("Reply with only one valid JSON object. No explanation and no code fences.")
        case .jsonSchema(let schema, _):
            parts.append("Reply with only one valid JSON object that matches this JSON Schema. No explanation and no code fences.\n\(schema)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "\n\n")
    }

    /// `history` with the instructions added to its system message (or as
    /// a new one at the start).
    func applying(to history: [ChatMessage]) -> [ChatMessage] {
        guard let instructions else { return history }
        var history = history
        if let index = history.firstIndex(where: { $0.role == .system }) {
            history[index].text += "\n\n" + instructions
        } else {
            history.insert(ChatMessage(role: .system, text: instructions), at: 0)
        }
        return history
    }

    /// The request's messages as chat history; nil if a role isn't known or
    /// `messages` is missing. The engine only knows system, user and
    /// assistant, so an assistant's earlier tool calls are written the way
    /// the model is asked to write them, and a tool's result becomes a user
    /// message.
    static func history(body: Data) -> [ChatMessage]? {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let messages = object["messages"] as? [[String: Any]]
        else { return nil }
        var history: [ChatMessage] = []
        for message in messages {
            guard let role = message["role"] as? String else { return nil }
            let content = text(ofContent: message["content"])
            switch role {
            case "system", "developer":
                history.append(ChatMessage(role: .system, text: content))
            case "user":
                history.append(ChatMessage(role: .user, text: content))
            case "assistant":
                let calls = (message["tool_calls"] as? [[String: Any]] ?? []).compactMap(render(call:))
                history.append(ChatMessage(role: .assistant, text: ([content] + calls).filter { !$0.isEmpty }.joined(separator: "\n")))
            case "tool", "function":
                let name = message["name"] as? String ?? message["tool_call_id"] as? String
                let label = name.map { "Result of the tool call \($0):" } ?? "Result of the tool call:"
                history.append(ChatMessage(role: .user, text: "\(label)\n\(content)"))
            default:
                return nil
            }
        }
        return history
    }

    /// A string, or the text parts of an array of typed parts.
    private static func text(ofContent content: Any?) -> String {
        if let text = content as? String { return text }
        guard let parts = content as? [[String: Any]] else { return "" }
        return parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: "\n")
    }

    /// An earlier tool call, in the tag the model is asked to use.
    private static func render(call: [String: Any]) -> String? {
        guard let function = call["function"] as? [String: Any], let name = function["name"] as? String else { return nil }
        var arguments: Any = [String: Any]()
        if let text = function["arguments"] as? String, let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) {
            arguments = parsed
        } else if let object = function["arguments"] as? [String: Any] {
            arguments = object
        }
        guard let body = self.text(of: ["name": name, "arguments": arguments]) else { return nil }
        return openTag + body + closeTag
    }

    // MARK: Reply

    /// Reads a finished reply: tool calls if it made any, else its text
    /// (as the JSON it holds, when JSON was asked for).
    func interpret(_ reply: String) -> Outcome {
        if usesTools {
            let calls = Self.toolCalls(in: reply, names: toolNames)
            if !calls.isEmpty { return .toolCalls(calls) }
        }
        let required: [String]
        switch format {
        case .text: return .content(reply, jsonValid: nil, missingKeys: [])
        case .jsonObject: required = []
        case .jsonSchema(_, let keys): required = keys
        }
        guard let json = Self.extractJSON(from: reply),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
        else { return .content(reply, jsonValid: false, missingKeys: []) }
        return .content(json, jsonValid: true, missingKeys: required.filter { object[$0] == nil })
    }

    /// Calls to known tools in `reply`: each `<tool_call>{…}` block (the
    /// closing tag may be missing), or a reply that is nothing but one such
    /// JSON object. A call to an unknown tool, or with arguments that
    /// aren't an object, is not a call.
    static func toolCalls(in reply: String, names: [String]) -> [ToolCall] {
        var candidates: [String] = []
        var rest = Substring(reply)
        while let open = rest.range(of: openTag) {
            let after = rest[open.upperBound...]
            if let close = after.range(of: closeTag) {
                candidates.append(String(after[..<close.lowerBound]))
                rest = after[close.upperBound...]
            } else {
                candidates.append(String(after))
                break
            }
        }
        if candidates.isEmpty { candidates = [reply] }
        var calls: [ToolCall] = []
        for candidate in candidates {
            guard let json = extractJSON(from: candidate),
                  let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
                  let name = object["name"] as? String, names.contains(name)
            else { continue }
            var arguments: [String: Any] = [:]
            if let object = object["arguments"] as? [String: Any] ?? object["parameters"] as? [String: Any] {
                arguments = object
            } else if let text = object["arguments"] as? String,
                      let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
                arguments = parsed
            } else if object["arguments"] != nil, !(object["arguments"] is NSNull) {
                continue
            }
            calls.append(ToolCall(
                index: calls.count,
                id: "call_" + UUID().uuidString.replacing("-", with: "").lowercased().prefix(24),
                function: .init(name: name, arguments: text(of: arguments) ?? "{}")
            ))
        }
        return calls
    }

    /// The first complete JSON object or array in `text`, e.g. inside code
    /// fences or after a sentence of preamble; nil if there is none.
    static func extractJSON(from text: String) -> String? {
        let characters = Array(text)
        var start = 0
        while start < characters.count {
            guard let open = characters[start...].firstIndex(where: { $0 == "{" || $0 == "[" }) else { return nil }
            if let end = matchingEnd(in: characters, from: open) {
                let candidate = String(characters[open...end])
                if (try? JSONSerialization.jsonObject(with: Data(candidate.utf8))) != nil { return candidate }
            }
            start = open + 1
        }
        return nil
    }

    /// The index of the bracket closing the one at `open`, skipping
    /// brackets inside strings.
    private static func matchingEnd(in characters: [Character], from open: Int) -> Int? {
        var depth = 0
        var inString = false
        var escaped = false
        for index in open..<characters.count {
            let character = characters[index]
            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{", "[": depth += 1
            case "}", "]":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }

    /// Compact JSON text, keys sorted and names untouched.
    private static func text(of value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

/// One tool call in a response, as OpenAI shapes it. `arguments` is JSON
/// text, as clients expect.
nonisolated struct ToolCall: Codable, Equatable, Sendable {
    struct Function: Codable, Equatable, Sendable {
        let name: String
        let arguments: String
    }

    /// Its position in the list; streamed deltas carry it.
    var index: Int?
    let id: String
    var type = "function"
    let function: Function

    static func == (lhs: ToolCall, rhs: ToolCall) -> Bool {
        // Ids are random; two calls are the same when they ask for the same thing.
        lhs.function == rhs.function && lhs.index == rhs.index
    }
}

/// SapientChat's note on a structured reply (not part of OpenAI's API):
/// whether the JSON that was asked for came back.
nonisolated struct StructuredNote: Codable, Equatable, Sendable {
    /// The reply is valid JSON.
    let jsonValid: Bool
    /// Required keys of the request's schema that the object lacks.
    var missingKeys: [String]?
}
