// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation
import UIKit

/// Runs API requests that other apps on this device hand over by opening a
/// `sapient://` URL (see `HandoffRequest`), then returns the result by
/// opening the caller's callback URL. One request at a time: a new one
/// replaces the one running.
@Observable
final class HandoffViewModel {
    enum State: Equatable {
        case idle
        case running(source: String?, path: String)
        case failed(String)
    }

    private(set) var state: State = .idle

    @ObservationIgnored private let router: ServeRouter
    @ObservationIgnored private let openURL: (URL) async -> Bool
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var current: HandoffRequest?

    init(router: ServeRouter, openURL: @escaping (URL) async -> Bool = { await UIApplication.shared.open($0) }) {
        self.router = router
        self.openURL = openURL
    }

    /// Whether `url` is a handoff this app should handle.
    static func handles(_ url: URL) -> Bool {
        url.scheme == HandoffRequest.scheme
    }

    func open(_ url: URL) {
        let handoff: HandoffRequest
        do {
            handoff = try HandoffRequest(url: url)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }
        task?.cancel()
        current = handoff
        state = .running(source: handoff.source, path: handoff.request.path)
        task = Task { [weak self] in await self?.run(handoff) }
    }

    /// Stops the request and tells the caller, if it asked to know.
    func cancel() {
        task?.cancel()
        task = nil
        let cancelURL = current?.cancelURL
        current = nil
        state = .idle
        if let cancelURL {
            Task { _ = await openURL(cancelURL) }
        }
    }

    func dismissError() {
        state = .idle
    }

    private func run(_ handoff: HandoffRequest) async {
        let response = await router.handle(handoff.request, source: handoff.source)
        var body = Data()
        do {
            switch response.body {
            case .data(let data): body = data
            case .stream(let chunks):
                for try await chunk in chunks { body.append(chunk) }
            }
        } catch {
            // Cancelled: `cancel()` already reported it.
            return
        }
        guard !Task.isCancelled else { return }
        current = nil
        guard let callback = handoff.callbackURL(status: response.status, body: body) else {
            // Nowhere to send it (e.g. a fire-and-forget load).
            state = .idle
            return
        }
        state = await openURL(callback) ? .idle : .failed("Couldn't return the result to \(handoff.source ?? "the calling app").")
    }
}
