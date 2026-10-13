// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation

/// What Sapient Studio is doing, as `GET /v1/activity` reports it.
struct Activity: Codable, Equatable {
    var active: Bool
    var title: String?
    var model: String?
    var phase: String?
    var label: String?
    var detail: String?
    var progress: Double?
    var tokens: Int?
    var tokensPerSecond: Double?
    var timeToFirstTokenMs: Int?
    var requests: Int?
    var startedAt: Double?
    var endedAt: Double?

    enum CodingKeys: String, CodingKey {
        case active, title, model, phase, label, detail, progress, tokens, requests
        case tokensPerSecond = "tokens_per_second"
        case timeToFirstTokenMs = "time_to_first_token_ms"
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }

    /// The server's own activity carries its address where others carry a model.
    var isServer: Bool { title == "API server" }
    var isOver: Bool { phase == "finished" || phase == "failed" }

    /// The one number worth showing small: requests while serving, percent
    /// with progress, speed while generating.
    var value: String? {
        if phase == "serving" || phase == "paused" { return "\(requests ?? 0)" }
        if let progress, !isOver { return "\(Int((progress * 100).rounded()))%" }
        if let tokensPerSecond { return String(format: "%.0f t/s", tokensPerSecond) }
        return nil
    }
}

/// Asks Sapient Studio's local server what it's doing, about once a second.
@MainActor
@Observable
final class ActivityFeed {
    /// The current activity; nil when the server is off or idle.
    private(set) var activity: Activity?

    private let url: URL
    private let session: URLSession
    private var task: Task<Void, Never>?

    init(port: Int) {
        url = URL(string: "http://127.0.0.1:\(port)/v1/activity")!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 2
        session = URLSession(configuration: configuration)
    }

    func start() {
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func refresh() async {
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let latest = try? JSONDecoder().decode(Activity.self, from: data), latest.active
        else {
            activity = nil
            return
        }
        activity = latest
    }
}
