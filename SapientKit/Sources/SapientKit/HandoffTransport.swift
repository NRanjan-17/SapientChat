import Foundation
import Synchronization
#if canImport(UIKit)
import UIKit
#endif

/// Hands requests to SapientChat on the same device by opening a
/// `sapient://` URL. SapientChat comes to the front, runs the request, and
/// opens your app's callback URL with the result. Use this on iPhone, where
/// iOS suspends SapientChat (and its server) while your app is in front.
///
/// Setup in your app:
/// 1. Register a URL scheme (Target → Info → URL Types), e.g. `myapp`, and
///    pass it as `callbackScheme`.
/// 2. Forward incoming URLs: `.onOpenURL { client.handle($0) }`.
/// 3. To check SapientChat is installed first, add `sapient` to
///    `LSApplicationQueriesSchemes` in your Info.plist.
///
/// Responses don't stream over a handoff.
public final class HandoffTransport: SapientTransport {
    public typealias Opener = @Sendable (URL) async -> Bool

    public let callbackScheme: String
    /// Your app's name, shown in SapientChat while the request runs.
    public let appName: String?
    public let apiKey: String?
    private let open: Opener
    private let pending = Mutex<[String: CheckedContinuation<(status: Int, body: Data), any Error>]>([:])

    /// The callback host this transport answers to.
    static let callbackHost = "sapient-callback"

    public init(callbackScheme: String, appName: String? = nil, apiKey: String? = nil, open: @escaping Opener) {
        self.callbackScheme = callbackScheme
        self.appName = appName
        self.apiKey = apiKey
        self.open = open
    }

    #if canImport(UIKit)
    /// Opens SapientChat with `UIApplication`.
    public convenience init(callbackScheme: String, appName: String? = nil, apiKey: String? = nil) {
        self.init(callbackScheme: callbackScheme, appName: appName, apiKey: apiKey) { @MainActor url in
            await UIApplication.shared.open(url, options: [:])
        }
    }

    /// Whether SapientChat is installed (needs `sapient` in your app's
    /// `LSApplicationQueriesSchemes`).
    @MainActor
    public static var isSapientInstalled: Bool {
        UIApplication.shared.canOpenURL(URL(string: "sapient://")!)
    }
    #endif

    public func send(method: String, path: String, body: Data?) async throws -> (status: Int, body: Data) {
        let id = UUID().uuidString
        let url = requestURL(id: id, method: method, path: path, body: body)
        return try await withCheckedThrowingContinuation { continuation in
            pending.withLock { $0[id] = continuation }
            Task {
                if !(await open(url)) {
                    resume(id, with: .failure(SapientError.unavailable("SapientChat isn't installed on this device.")))
                }
            }
        }
    }

    public func events(path: String, body: Data) -> AsyncThrowingStream<Data, any Error>? {
        nil
    }

    /// Completes the request a callback URL answers. Returns false for URLs
    /// that aren't SapientChat callbacks, so you can handle those yourself.
    @discardableResult
    public func handle(_ url: URL) -> Bool {
        guard url.scheme == callbackScheme, url.host() == Self.callbackHost,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            query[item.name] = item.value ?? ""
        }
        guard let id = query["id"] else { return false }
        switch url.path() {
        case "/cancel":
            resume(id, with: .failure(SapientError.cancelled))
        case "/success", "/error":
            guard let status = query["status"].flatMap(Int.init),
                  let body = Base64URL.decode(query["body"] ?? "")
            else {
                resume(id, with: .failure(SapientError.invalidResponse))
                return true
            }
            resume(id, with: .success((status, body)))
        default:
            return false
        }
        return true
    }

    /// Requests waiting for SapientChat's callback.
    var pendingIDsForTesting: [String] {
        pending.withLock { Array($0.keys) }
    }

    /// The `sapient://` URL for one request.
    func requestURL(id: String, method: String, path: String, body: Data?) -> URL {
        var components = URLComponents()
        components.scheme = "sapient"
        components.host = "x-callback-url"
        components.path = "/request"
        var items = [
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "method", value: method),
            URLQueryItem(name: "x-success", value: callbackURL("success", id: id)),
            URLQueryItem(name: "x-error", value: callbackURL("error", id: id)),
            URLQueryItem(name: "x-cancel", value: callbackURL("cancel", id: id)),
        ]
        if let body { items.append(URLQueryItem(name: "body", value: Base64URL.encode(body))) }
        if let appName { items.append(URLQueryItem(name: "x-source", value: appName)) }
        if let apiKey, !apiKey.isEmpty { items.append(URLQueryItem(name: "key", value: apiKey)) }
        components.queryItems = items
        // `+` is legal in a query but read as a space by some parsers.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacing("+", with: "%2B")
        return components.url!
    }

    private func callbackURL(_ outcome: String, id: String) -> String {
        "\(callbackScheme)://\(Self.callbackHost)/\(outcome)?id=\(id)"
    }

    private func resume(_ id: String, with result: Result<(status: Int, body: Data), any Error>) {
        pending.withLock { $0.removeValue(forKey: id) }?.resume(with: result)
    }
}

/// URL-safe base64 without padding (RFC 4648 §5), as SapientChat uses.
enum Base64URL {
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
