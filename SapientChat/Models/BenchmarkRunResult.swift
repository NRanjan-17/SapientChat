/// One timed generation.
nonisolated struct BenchmarkRunResult: Identifiable, Equatable, Sendable, Codable {
    /// 1-based within its group (warm-up or measured).
    let index: Int
    let isWarmup: Bool
    let ttftMs: UInt64
    let elapsedMs: UInt64
    let tokens: Int
    let decodeTokensPerSecond: Double
    let prefillTokensPerSecond: Double
    /// Ended on end-of-turn before the token limit, so it measured fewer tokens.
    let hitEndOfTurn: Bool
    let footprintBytes: UInt64?

    var id: String { "\(isWarmup ? "w" : "r")\(index)" }
}
