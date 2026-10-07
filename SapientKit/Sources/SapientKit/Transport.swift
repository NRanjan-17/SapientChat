import Foundation

/// How requests reach SapientChat.
public protocol SapientTransport: Sendable {
    /// Sends one request and returns the status and body.
    func send(method: String, path: String, body: Data?) async throws -> (status: Int, body: Data)

    /// Streams the `data:` payloads of a server-sent event response, ending
    /// at `[DONE]`. Nil when this transport can't stream; the client then
    /// falls back to one `send`.
    func events(path: String, body: Data) -> AsyncThrowingStream<Data, any Error>?
}

/// Calls SapientChat's API server over HTTP: from another device, from an
/// app beside SapientChat on iPad, or from a Mac.
public struct HTTPTransport: SapientTransport {
    public let baseURL: URL
    public let apiKey: String?
    let session: URLSession

    /// `baseURL` is an address the API Server screen shows, e.g.
    /// `http://192.168.1.20:11435`.
    public init(baseURL: URL, apiKey: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    public func send(method: String, path: String, body: Data?) async throws -> (status: Int, body: Data) {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request(method: method, path: path, body: body))
        } catch let error as URLError where Self.isUnreachable(error) {
            throw SapientError.unavailable("Can't reach SapientChat at \(baseURL.absoluteString): \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { throw SapientError.invalidResponse }
        return (http.statusCode, data)
    }

    public func events(path: String, body: Data) -> AsyncThrowingStream<Data, any Error>? {
        let request = request(method: "POST", path: path, body: body)
        let session = session
        let baseURL = baseURL
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else { throw SapientError.invalidResponse }
                    guard http.statusCode < 400 else {
                        var data = Data()
                        for try await byte in bytes { data.append(byte) }
                        throw SapientClient.apiError(status: http.statusCode, body: data)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        let data = Data(payload.utf8)
                        // An error after the stream started arrives as an event.
                        if let error = try? JSON.decoder.decode(ErrorBody.self, from: data) {
                            throw SapientError.api(status: 500, message: error.error.message)
                        }
                        continuation.yield(data)
                    }
                    continuation.finish()
                } catch let error as URLError where Self.isUnreachable(error) {
                    continuation.finish(throwing: SapientError.unavailable(
                        "Can't reach SapientChat at \(baseURL.absoluteString): \(error.localizedDescription)"
                    ))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func request(method: String, path: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        // Loading a model can take a while on first use.
        request.timeoutInterval = 600
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        return request
    }

    static func isUnreachable(_ error: URLError) -> Bool {
        [.cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet, .timedOut]
            .contains(error.code)
    }
}

/// Tries HTTP first and, when SapientChat can't be reached that way (it's
/// suspended in the background on this iPhone), hands the request over.
public struct FallbackTransport: SapientTransport {
    public let primary: HTTPTransport
    public let fallback: HandoffTransport

    public init(primary: HTTPTransport, fallback: HandoffTransport) {
        self.primary = primary
        self.fallback = fallback
    }

    public func send(method: String, path: String, body: Data?) async throws -> (status: Int, body: Data) {
        do {
            return try await primary.send(method: method, path: path, body: body)
        } catch SapientError.unavailable {
            return try await fallback.send(method: method, path: path, body: body)
        }
    }

    /// Streaming needs the server; without it the client sends one request.
    public func events(path: String, body: Data) -> AsyncThrowingStream<Data, any Error>? {
        nil
    }
}
