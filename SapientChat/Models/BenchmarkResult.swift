import Foundation

/// Everything one benchmark measured, in app terms (no engine types), so it
/// can be shown, tested and exported as JSON.
nonisolated struct BenchmarkResult: Equatable, Sendable, Codable {
    let model: String
    let backend: String
    let isMemoryMapped: Bool
    let contextLength: Int
    let loadTimeMs: UInt64
    let promptTokens: Int
    let maxTokens: Int
    let warmupRuns: [BenchmarkRunResult]
    let runs: [BenchmarkRunResult]
    let meanTtftMs: UInt64
    let meanDecodeTokensPerSecond: Double
    let minDecodeTokensPerSecond: Double
    let maxDecodeTokensPerSecond: Double
    let meanPrefillTokensPerSecond: Double
    let peakFootprintBytes: UInt64?
    let thermalStart: String
    let thermalEnd: String
    let cancelled: Bool
    let engineVersion: String
    let method: String
    /// The numbers came from the simulator, i.e. from the Mac, not a phone.
    let isSimulator: Bool

    /// Pretty-printed JSON for sharing.
    func jsonText() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }
}
