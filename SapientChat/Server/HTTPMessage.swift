// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// One parsed HTTP/1.1 request.
nonisolated struct HTTPRequest: Sendable {
    var method: String
    /// The path without its query string, e.g. `/api/chat`.
    var path: String
    var query: [String: String] = [:]
    /// Header names lowercased.
    var headers: [String: String] = [:]
    var body = Data()

    func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

/// Turns the bytes received so far into a request. Pure, so it is
/// unit-testable without a socket.
nonisolated enum HTTPRequestParser {
    static let maxHeaderBytes = 64 * 1024
    static let maxBodyBytes = 16 * 1024 * 1024

    enum Result: Sendable {
        /// Keep reading.
        case incomplete
        case complete(HTTPRequest)
        case invalid(status: Int, reason: String)
    }

    static func parse(_ data: Data) -> Result {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.firstRange(of: separator) else {
            return data.count > maxHeaderBytes ? .invalid(status: 431, reason: "Headers too large") : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else {
            return .invalid(status: 400, reason: "Headers are not UTF-8")
        }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else {
            return .invalid(status: 400, reason: "Malformed request line")
        }

        var headers: [String: String] = [:]
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                return .invalid(status: 400, reason: "Malformed header")
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = value
        }
        if headers["transfer-encoding"]?.lowercased().contains("chunked") == true {
            return .invalid(status: 411, reason: "Chunked request bodies are not supported; send Content-Length")
        }

        let length: Int
        if let value = headers["content-length"] {
            guard let parsed = Int(value), parsed >= 0 else {
                return .invalid(status: 400, reason: "Bad Content-Length")
            }
            length = parsed
        } else {
            length = 0
        }
        guard length <= maxBodyBytes else { return .invalid(status: 413, reason: "Body too large") }
        let bodyStart = headerEnd.upperBound
        guard data.distance(from: bodyStart, to: data.endIndex) >= length else { return .incomplete }

        let target = String(requestLine[1])
        let components = URLComponents(string: target)
        var query: [String: String] = [:]
        for item in components?.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        let body = Data(data[bodyStart..<data.index(bodyStart, offsetBy: length)])
        return .complete(HTTPRequest(
            method: requestLine[0].uppercased(),
            path: components?.path ?? target,
            query: query,
            headers: headers,
            body: body
        ))
    }
}

/// A response: a complete body, or a stream of chunks sent with chunked
/// transfer encoding as they are produced (server-sent events).
nonisolated struct HTTPResponse: Sendable {
    enum Body: Sendable {
        case data(Data)
        case stream(AsyncThrowingStream<Data, any Error>)
    }

    var status: Int
    var contentType: String
    var headers: [String: String] = [:]
    var body: Body

    /// Pretty-printed, ending in a newline so a shell prompt starts on its own line.
    static func json<Value: Encodable>(_ value: Value, status: Int = 200) -> HTTPResponse {
        var data = (try? APIJSON.prettyEncoder.encode(value)) ?? Data("{}".utf8)
        data.append(0x0A)
        return HTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: .data(data))
    }

    static func text(_ text: String, status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: .data(Data(text.utf8)))
    }

    static func empty(status: Int = 200) -> HTTPResponse {
        HTTPResponse(status: status, contentType: "text/plain; charset=utf-8", body: .data(Data()))
    }

    /// Status line and headers, ending with the blank line. Every response
    /// closes the connection, and allows any web origin (CORS) so browser
    /// clients can call the device directly.
    func head() -> Data {
        var lines = ["HTTP/1.1 \(status) \(Self.reason(for: status))"]
        var fields = headers
        fields["Content-Type"] = contentType
        fields["Connection"] = "close"
        fields["Access-Control-Allow-Origin"] = "*"
        fields["Access-Control-Allow-Headers"] = "Authorization, Content-Type"
        fields["Access-Control-Allow-Methods"] = "GET, POST, OPTIONS"
        switch body {
        case .data(let data): fields["Content-Length"] = String(data.count)
        case .stream:
            fields["Transfer-Encoding"] = "chunked"
            fields["Cache-Control"] = "no-cache"
        }
        for (name, value) in fields.sorted(by: { $0.key < $1.key }) {
            lines.append("\(name): \(value)")
        }
        return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }

    /// One chunk in chunked transfer encoding (empty data = the final chunk).
    static func chunk(_ data: Data) -> Data {
        var framed = Data((String(data.count, radix: 16) + "\r\n").utf8)
        framed.append(data)
        framed.append(Data("\r\n".utf8))
        return framed
    }

    static func reason(for status: Int) -> String {
        switch status {
        case 200: "OK"
        case 204: "No Content"
        case 400: "Bad Request"
        case 401: "Unauthorized"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 411: "Length Required"
        case 413: "Payload Too Large"
        case 431: "Request Header Fields Too Large"
        case 500: "Internal Server Error"
        case 503: "Service Unavailable"
        case 422: "Unprocessable Entity"
        case 501: "Not Implemented"
        default: "Status"
        }
    }
}

/// The JSON coding `sapient serve` and OpenAI clients use: snake_case keys.
nonisolated enum APIJSON {
    /// Compact, keys sorted: one server-sent event must be one line.
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return encoder
    }

    /// Indented, keys sorted: plain JSON replies, easy to read in a terminal.
    static var prettyEncoder: JSONEncoder {
        let encoder = encoder
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys, .prettyPrinted]
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    /// One server-sent event carrying `value` as JSON.
    static func event<Value: Encodable>(_ value: Value) -> Data {
        var data = Data("data: ".utf8)
        data.append((try? encoder.encode(value)) ?? Data("{}".utf8))
        data.append(Data("\n\n".utf8))
        return data
    }
}
