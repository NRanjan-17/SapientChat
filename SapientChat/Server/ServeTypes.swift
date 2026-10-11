// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

// Request and response bodies of `sapient serve`'s OpenAI-compatible API
// (crates/sapient-cli/src/server.rs), coded as snake_case by `APIJSON`.
// Fields the on-device engine can't honor per request (temperature, images)
// aren't decoded, so clients that send them still work.

/// `{"error": {"message", "type", "code"?}}`, as `sapient serve` sends.
nonisolated struct ServeErrorBody: Codable, Sendable {
    struct Detail: Codable, Sendable {
        let message: String
        let type: String
        var code: String?
    }

    let error: Detail

    static func invalidRequest(_ message: String) -> ServeErrorBody {
        ServeErrorBody(error: Detail(message: message, type: "invalid_request_error"))
    }

    static func modelNotFound(_ message: String) -> ServeErrorBody {
        ServeErrorBody(error: Detail(message: message, type: "invalid_request_error", code: "model_not_found"))
    }

    /// A download or load problem: its message says what to do next, and
    /// `code` (e.g. "no_network", "storage_full") lets a client act on it.
    static func problem(_ problem: AppProblem) -> ServeErrorBody {
        ServeErrorBody(error: Detail(message: problem.summary, type: "model_unavailable", code: problem.code))
    }

    static func server(_ message: String) -> ServeErrorBody {
        ServeErrorBody(error: Detail(message: message, type: "server_error"))
    }
}

/// `stop` is a string or an array of strings.
nonisolated struct StopSequences: Codable, Sendable {
    let values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let one = try? container.decode(String.self) {
            values = [one]
        } else {
            values = (try? container.decode([String].self)) ?? []
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

nonisolated struct ChatCompletionRequest: Codable, Sendable {
    /// Empty or missing: the most recently used loaded model.
    var model: String?
    let messages: [ServeMessage]
    var stream: Bool?
    var maxTokens: Int?
    var stop: StopSequences?
    var tools: [AnyCodable]?
}

nonisolated struct CompletionRequest: Codable, Sendable {
    var model: String?
    let prompt: String
    var stream: Bool?
    var maxTokens: Int?
    var stop: StopSequences?
}

/// A chat message. `content` is a string, an array of typed parts (only
/// text parts are used), or null.
nonisolated struct ServeMessage: Codable, Sendable {
    let role: String
    let content: String

    private enum CodingKeys: String, CodingKey { case role, content }
    private struct Part: Codable { let type: String; let text: String? }

    init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decode(String.self, forKey: .role)
        if let text = try? container.decode(String.self, forKey: .content) {
            content = text
        } else if let parts = try? container.decode([Part].self, forKey: .content) {
            content = parts.compactMap { $0.type == "text" ? $0.text : nil }.joined(separator: "\n")
        } else {
            content = ""
        }
    }
}

nonisolated struct Usage: Codable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

nonisolated struct ChatCompletionResponse: Codable, Sendable {
    struct Choice: Codable, Sendable {
        let index: Int
        let message: ServeMessage
        let finishReason: String
    }

    let id: String
    var object = "chat.completion"
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage
}

nonisolated struct ChatCompletionChunk: Codable, Sendable {
    struct Delta: Codable, Sendable {
        var role: String?
        var content: String?
    }

    struct Choice: Codable, Sendable {
        let index: Int
        let delta: Delta
        var finishReason: String?
    }

    let id: String
    var object = "chat.completion.chunk"
    let created: Int
    let model: String
    let choices: [Choice]
    var usage: Usage?
}

nonisolated struct CompletionResponse: Codable, Sendable {
    struct Choice: Codable, Sendable {
        let index: Int
        let text: String
        var finishReason: String?
    }

    let id: String
    var object = "text_completion"
    let created: Int
    let model: String
    let choices: [Choice]
    var usage: Usage?
}

nonisolated struct ModelList: Codable, Sendable {
    struct Model: Codable, Sendable {
        let id: String
        var object = "model"
        var ownedBy = "sapient"
        let created: Int
    }

    var object = "list"
    let data: [Model]
    let activeModel: String?
    let residentModels: [String]
}

/// `GET /v1/ping`: the server is up. No model or memory work.
nonisolated struct PingResponse: Codable, Sendable {
    var status = "ok"
    let version: String
}

nonisolated struct HealthResponse: Codable, Sendable {
    var status = "ok"
    let version: String
    let loadedModel: String?
    let residentModels: [String]
    var audioModels: [String] = []
    var vlaModels: [String] = []
    /// SapientChat additions: the slot count, memory and thermal state.
    var maxResidentModels: Int?
    var device: DeviceHealth?
}

/// Any JSON value, kept only to notice that a field was sent.
nonisolated struct AnyCodable: Codable, Sendable {
    init(from decoder: any Decoder) throws {}
    func encode(to encoder: any Encoder) throws {}
}

// MARK: Model management (SapientChat additions; `sapient serve` has no
// equivalent, since the desktop server loads models on demand only)

/// Body of the `/v1/models/…` calls.
nonisolated struct ModelActionRequest: Codable, Sendable {
    /// Omitted on `unload`: unload every model.
    var model: String?
    /// `download` only: send progress as server-sent events.
    var stream: Bool?
}

/// Every model this device offers, with where it stands.
nonisolated struct CatalogResponse: Codable, Sendable {
    struct Model: Codable, Sendable {
        let id: String
        let name: String
        /// e.g. "135M Q4_K_M".
        let params: String
        let format: String
        let parameterBillions: Double
        /// Rough memory once loaded; a go/no-go estimate, not a measurement.
        let estimatedMemoryBytes: UInt64
        let downloaded: Bool
        /// Bytes on disk, complete or partial.
        let downloadedBytes: UInt64
        let loaded: Bool
        /// Whether it should fit in memory now (releasing other models if needed).
        let fits: Bool
        /// The two sizes above for people: "1.5 GB".
        let memory: String
        let sizeOnDisk: String
        /// Sampling temperature; absent means Precise (greedy).
        var temperature: Double?
        /// Context window in tokens; absent means the engine's default.
        var contextWindow: Int?
    }

    var object = "list"
    let data: [Model]
    let residentModels: [String]
    let maxResidentModels: Int
}

/// The result of load, unload, download and delete.
nonisolated struct ModelActionResponse: Codable, Sendable {
    /// The model acted on; nil when every model was unloaded.
    let model: String?
    /// "loaded", "unloaded", "downloaded" or "deleted".
    let status: String
    /// Hardware the model runs on, e.g. "Metal GPU" (load only).
    var backend: String?
    let residentModels: [String]
}

/// One `download` progress event.
nonisolated struct DownloadEvent: Codable, Sendable {
    let model: String
    /// "downloading", then "downloaded".
    let status: String
    let downloadedBytes: UInt64
    /// 0 when the size isn't known yet.
    let totalBytes: UInt64
    /// For people: "45%" (nil until the size is known), "412 MB of 1.1 GB".
    var progress: String?
    var size: String?

    init(model: String, status: String, downloadedBytes: UInt64, totalBytes: UInt64) {
        self.model = model
        self.status = status
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
        if totalBytes > 0 {
            progress = "\(min(100, downloadedBytes * 100 / totalBytes))%"
            size = "\(Format.bytes(downloadedBytes)) of \(Format.bytes(totalBytes))"
        }
    }
}

/// The device side of `/v1/health`.
nonisolated struct DeviceHealth: Codable, Sendable {
    let footprintBytes: UInt64?
    /// What iOS still lets the app allocate; nil when there's no limit.
    let availableBytes: UInt64?
    /// "nominal", "fair", "serious" or "critical".
    let thermal: String
}

extension AppProblem {
    /// The HTTP status an API response for this problem carries.
    var httpStatus: Int {
        switch kind {
        case .noNetwork, .hubUnreachable, .hubError, .interrupted, .downloadFailed: 502
        case .rateLimited: 429
        case .accessDenied: 403
        case .notFound: 404
        case .storageFull, .notEnoughMemory: 507
        case .memoryBusy, .modelReleased, .closedWhileLoading: 503
        case .loadFailed: 500
        }
    }
}

/// `GET /v1/models/settings?model=…`, and the answer to a `POST` there:
/// a model's sampling temperature and context window, which SAPIENT applies
/// when the model loads. `null` means the default.
nonisolated struct ModelSettingsResponse: Codable, Sendable {
    let model: String
    /// Sampling temperature; null is Precise (greedy: the same prompt
    /// always gets the same answer).
    let temperature: Double?
    /// Lowest and highest temperature accepted.
    let temperatureRange: [Double]
    /// Context window in tokens; null is the engine's default.
    let contextWindow: Int?
    /// Only models of 1.4B and up can pick their context window.
    let contextWindowAdjustable: Bool
    let contextWindowChoices: [Int]
    let loaded: Bool
    /// On a POST: whether anything changed, and whether the model was
    /// reloaded so the next request uses it.
    var updated: Bool?
    var reloaded: Bool?

    private enum CodingKeys: String, CodingKey {
        case model, temperature, temperatureRange, contextWindow, contextWindowAdjustable, contextWindowChoices
        case loaded, updated, reloaded
    }

    init(model: String, temperature: Double?, contextWindow: Int?, adjustable: Bool, loaded: Bool,
         updated: Bool? = nil, reloaded: Bool? = nil) {
        self.model = model
        self.temperature = temperature
        temperatureRange = [TemperatureStore.range.lowerBound, TemperatureStore.range.upperBound]
        self.contextWindow = contextWindow
        contextWindowAdjustable = adjustable
        contextWindowChoices = adjustable ? ContextWindowStore.choices : []
        self.loaded = loaded
        self.updated = updated
        self.reloaded = reloaded
    }

    /// Writes `null` for a default instead of leaving the key out, so a
    /// client sees every setting.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(temperatureRange, forKey: .temperatureRange)
        try container.encode(contextWindow, forKey: .contextWindow)
        try container.encode(contextWindowAdjustable, forKey: .contextWindowAdjustable)
        try container.encode(contextWindowChoices, forKey: .contextWindowChoices)
        try container.encode(loaded, forKey: .loaded)
        try container.encodeIfPresent(updated, forKey: .updated)
        try container.encodeIfPresent(reloaded, forKey: .reloaded)
    }
}
