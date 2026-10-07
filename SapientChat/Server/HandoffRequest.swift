import Foundation

/// An API call from another app on this device, made by opening a
/// `sapient://` URL. iOS suspends SapientChat in the background, so a
/// same-device app can't reach the HTTP server while it's in front; it
/// hands the request over instead. SapientChat comes to the front, runs it
/// through the same API, and opens the caller's callback URL with the result
/// (x-callback-url conventions):
///
///     sapient://x-callback-url/request
///       ?path=/v1/chat/completions      any API route
///       &method=POST                    default: POST with a body, else GET
///       &body=<base64url JSON>          the request body
///       &key=<API key>                  when the server has one set
///       &x-source=<app name>            shown while the request runs
///       &x-success=<url>                gets ?status=<code>&body=<base64url JSON>
///       &x-error=<url>                  same, plus error=<message>, on 4xx/5xx
///       &x-cancel=<url>                 opened if the user cancels
///
/// Responses never stream over a handoff: `stream: true` is turned off.
nonisolated struct HandoffRequest: Sendable {
    static let scheme = "sapient"

    let request: HTTPRequest
    /// The calling app's name, if it gave one.
    let source: String?
    let successURL: URL?
    let errorURL: URL?
    let cancelURL: URL?

    enum ParseError: Error, Equatable, LocalizedError {
        case notAHandoff
        case missingPath
        case badBody

        var errorDescription: String? {
            switch self {
            case .notAHandoff: "Not a SapientChat request."
            case .missingPath: "The request didn't say which API route to call."
            case .badBody: "The request body isn't base64url-encoded JSON."
            }
        }
    }

    init(url: URL) throws(ParseError) {
        guard url.scheme == Self.scheme, url.host() == "x-callback-url", url.path() == "/request",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw .notAHandoff }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        guard let path = query["path"], path.hasPrefix("/v1/") else { throw .missingPath }

        var body = Data()
        if let encoded = query["body"], !encoded.isEmpty {
            guard let decoded = Base64URL.decode(encoded),
                  (try? JSONSerialization.jsonObject(with: decoded)) != nil
            else { throw .badBody }
            body = Self.withoutStreaming(decoded)
        }
        var headers = ["content-type": "application/json", "content-length": String(body.count)]
        if let key = query["key"], !key.isEmpty {
            headers["authorization"] = "Bearer \(key)"
        }
        request = HTTPRequest(
            method: query["method"]?.uppercased() ?? (body.isEmpty ? "GET" : "POST"),
            path: path,
            headers: headers,
            body: body
        )
        source = query["x-source"].flatMap { $0.isEmpty ? nil : $0 }
        successURL = query["x-success"].flatMap(URL.init(string:))
        errorURL = query["x-error"].flatMap(URL.init(string:))
        cancelURL = query["x-cancel"].flatMap(URL.init(string:))
    }

    /// Where to send a response: x-error for failures (x-success if the
    /// caller gave no x-error), with the status and body appended.
    func callbackURL(status: Int, body: Data) -> URL? {
        let failed = status >= 400
        guard let base = failed ? (errorURL ?? successURL) : successURL,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else { return nil }
        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "status", value: String(status)))
        items.append(URLQueryItem(name: "body", value: Base64URL.encode(body)))
        if failed {
            items.append(URLQueryItem(name: "error", value: Self.errorMessage(in: body) ?? HTTPResponse.reason(for: status)))
        }
        components.queryItems = items
        return components.url
    }

    /// `{"error": {"message": …}}` → the message.
    private static func errorMessage(in body: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let error = object["error"] as? [String: Any]
        else { return nil }
        return error["message"] as? String
    }

    /// The body with `"stream": false`, since a callback carries one response.
    private static func withoutStreaming(_ body: Data) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["stream"] as? Bool == true
        else { return body }
        object["stream"] = false
        return (try? JSONSerialization.data(withJSONObject: object)) ?? body
    }
}

/// URL-safe base64 without padding (RFC 4648 §5).
nonisolated enum Base64URL {
    static func encode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    static func decode(_ string: String) -> Data? {
        var base64 = string.replacing("-", with: "+").replacing("_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
