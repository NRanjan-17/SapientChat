// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Who sent an API request, for the request log: the app, and the device
/// it came from.
///
/// The app comes from, in order: the `X-Sapient-Client` header (SapientKit
/// sends the app's name; any client can set it), the app name a URL handoff
/// gave (`x-source`), or the `User-Agent`: iOS and macOS apps send
/// `AppName/1 CFNetwork/… Darwin/…`, and curl, Python, Node and browsers
/// name themselves too. None of these is proof: a client can claim any name.
nonisolated struct ClientIdentity: Equatable, Sendable {
    static let header = "X-Sapient-Client"
    static let thisDevice = "This device"

    /// e.g. "Notes Helper", "curl", "Safari"; nil when nothing says.
    let app: String?
    /// "This device", or the caller's IP address.
    let device: String?
    let userAgent: String?

    static func of(_ request: HTTPRequest, handoffSource: String? = nil) -> ClientIdentity {
        let userAgent = request.header("User-Agent").flatMap { $0.isEmpty ? nil : $0 }
        // SapientKit percent-encodes what a header can't carry (e.g. "Café").
        let named = request.header(header)
            .map { ($0.removingPercentEncoding ?? $0).trimmingCharacters(in: .whitespaces) }
            .flatMap { $0.isEmpty ? nil : $0 }
        let app = named ?? handoffSource ?? userAgent.flatMap(appName(fromUserAgent:))
        let device = handoffSource != nil ? thisDevice : request.remoteAddress.map(deviceName)
        return ClientIdentity(app: app, device: device, userAgent: userAgent)
    }

    /// The app or tool a `User-Agent` names.
    static func appName(fromUserAgent agent: String) -> String? {
        let lower = agent.lowercased()
        if lower.hasPrefix("mozilla/") {
            if lower.contains("edg/") { return "Edge" }
            if lower.contains("firefox/") || lower.contains("fxios/") { return "Firefox" }
            if lower.contains("chrome/") || lower.contains("crios/") { return "Chrome" }
            if lower.contains("safari/") { return "Safari" }
            return "Web browser"
        }
        let known: [(prefix: String, name: String)] = [
            ("curl/", "curl"), ("wget/", "Wget"), ("python-requests/", "Python (requests)"),
            ("python-httpx/", "Python (httpx)"), ("python-urllib/", "Python (urllib)"), ("aiohttp/", "Python (aiohttp)"),
            ("openai/python", "OpenAI Python SDK"), ("openai/js", "OpenAI JS SDK"), ("node-fetch", "Node.js"),
            ("node", "Node.js"), ("undici", "Node.js"), ("axios/", "axios"), ("postmanruntime/", "Postman"),
            ("insomnia/", "Insomnia"), ("okhttp/", "Android app (OkHttp)"), ("dart:io", "Dart / Flutter"),
            ("go-http-client/", "Go"), ("sapientkit/", "SapientKit app"),
        ]
        if let match = known.first(where: { lower.hasPrefix($0.prefix) }) { return match.name }
        // "My%20App/12 CFNetwork/1568 Darwin/25.0.0" → "My App".
        guard let product = agent.split(separator: " ").first?.split(separator: "/").first, !product.isEmpty else { return nil }
        return String(product).removingPercentEncoding ?? String(product)
    }

    /// "This device" for loopback, else the address without an IPv6 zone.
    static func deviceName(_ address: String) -> String {
        let host = address.split(separator: "%").first.map(String.init) ?? address
        let loopback = ["127.0.0.1", "::1", "::ffff:127.0.0.1", "localhost"]
        return loopback.contains(host) || host.hasPrefix("127.") ? thisDevice : host
    }
}
