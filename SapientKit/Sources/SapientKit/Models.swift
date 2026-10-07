import Foundation

/// One chat message.
public struct Message: Codable, Sendable, Equatable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    public static func system(_ content: String) -> Message { Message(role: "system", content: content) }
    public static func user(_ content: String) -> Message { Message(role: "user", content: content) }
    public static func assistant(_ content: String) -> Message { Message(role: "assistant", content: content) }
}

public struct Usage: Codable, Sendable, Equatable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int
}

/// A finished chat or completion.
public struct GenerationResult: Sendable, Equatable {
    public let id: String
    /// The model that answered.
    public let model: String
    public let text: String
    public let finishReason: String
    public let usage: Usage
}

/// `GET /v1/health`: the engine and device right now.
public struct Health: Codable, Sendable, Equatable {
    public struct Device: Codable, Sendable, Equatable {
        public let footprintBytes: UInt64?
        /// What iOS still lets SapientChat allocate; nil when there's no limit.
        public let availableBytes: UInt64?
        /// "nominal", "fair", "serious" or "critical".
        public let thermal: String
    }

    public let status: String
    /// The SAPIENT engine version.
    public let version: String
    /// The most recently used loaded model.
    public let loadedModel: String?
    public let residentModels: [String]
    public let maxResidentModels: Int?
    public let device: Device?
}

/// `GET /v1/catalog`: every model the device offers.
public struct Catalog: Codable, Sendable, Equatable {
    public struct Model: Codable, Sendable, Equatable, Identifiable {
        /// What to pass as `model`, e.g. "openhorizon/qwen2.5-0.5b".
        public let id: String
        public let name: String
        public let params: String
        public let format: String
        public let parameterBillions: Double
        public let estimatedMemoryBytes: UInt64
        public let downloaded: Bool
        public let downloadedBytes: UInt64
        public let loaded: Bool
        /// Whether it should fit in memory now.
        public let fits: Bool
    }

    public let data: [Model]
    public let residentModels: [String]
    public let maxResidentModels: Int

    public var models: [Model] { data }
}

/// `GET /v1/models`: the downloaded models.
public struct ModelList: Codable, Sendable, Equatable {
    public struct Model: Codable, Sendable, Equatable {
        public let id: String
    }

    public let data: [Model]
    public let activeModel: String?
    public let residentModels: [String]

    public var ids: [String] { data.map(\.id) }
}

/// The result of download, load, unload and delete.
public struct ModelActionResult: Codable, Sendable, Equatable {
    public let model: String?
    /// "downloaded", "loaded", "unloaded" or "deleted".
    public let status: String
    /// Hardware the model runs on, e.g. "Metal GPU" (load only).
    public let backend: String?
    public let residentModels: [String]
}

/// Download progress.
public struct DownloadEvent: Codable, Sendable, Equatable {
    public let model: String
    /// "downloading", then "downloaded".
    public let status: String
    public let downloadedBytes: UInt64
    /// 0 when the size isn't known yet.
    public let totalBytes: UInt64

    /// 0…1, or nil when the total is unknown.
    public var fraction: Double? {
        totalBytes > 0 ? min(1, Double(downloadedBytes) / Double(totalBytes)) : nil
    }
}

public enum SapientError: Error, Sendable, Equatable, LocalizedError {
    /// The API answered with an error.
    case api(status: Int, message: String)
    /// SapientChat isn't installed (handoff) or can't be reached (HTTP).
    case unavailable(String)
    /// The user cancelled the request in SapientChat.
    case cancelled
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case .api(let status, let message): "SapientChat error \(status): \(message)"
        case .unavailable(let reason): reason
        case .cancelled: "The request was cancelled in SapientChat."
        case .invalidResponse: "SapientChat sent a response this version of SapientKit can't read."
        }
    }
}

// MARK: Wire types

struct ChatRequestBody: Encodable {
    var model: String?
    var messages: [Message]
    var stream: Bool
    var maxTokens: Int?
    var stop: [String]?
}

struct CompletionRequestBody: Encodable {
    var model: String?
    var prompt: String
    var stream: Bool
    var maxTokens: Int?
    var stop: [String]?
}

struct ModelActionBody: Encodable {
    var model: String?
    var stream: Bool?
}

struct ChatResponseBody: Decodable {
    struct Choice: Decodable {
        let message: Message
        let finishReason: String
    }

    let id: String
    let model: String
    let choices: [Choice]
    let usage: Usage
}

struct CompletionResponseBody: Decodable {
    struct Choice: Decodable {
        let text: String
        let finishReason: String?
    }

    let id: String
    let model: String
    let choices: [Choice]
    let usage: Usage?
}

struct ChatChunkBody: Decodable {
    struct Delta: Decodable { let content: String? }
    struct Choice: Decodable { let delta: Delta }
    let choices: [Choice]
}

struct ErrorBody: Decodable {
    struct Detail: Decodable { let message: String }
    let error: Detail
}

enum JSON {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }
}
