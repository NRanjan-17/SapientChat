/// Averages over one chat's measured replies.
nonisolated struct ChatStatsSummary: Equatable, Sendable {
    let replies: Int
    let averageTokensPerSecond: Double?
    let bestTokensPerSecond: Double?
    let averageFirstTokenMs: Int?

    init(_ stats: [ReplyStats]) {
        replies = stats.count
        let speeds = stats.compactMap(\.tokensPerSecond)
        averageTokensPerSecond = speeds.isEmpty ? nil : speeds.reduce(0, +) / Double(speeds.count)
        bestTokensPerSecond = speeds.max()
        averageFirstTokenMs = stats.isEmpty ? nil : stats.map(\.firstTokenMs).reduce(0, +) / stats.count
    }
}
