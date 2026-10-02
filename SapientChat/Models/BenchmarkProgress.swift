/// Benchmark progress: runs finished out of the total (warm-up included).
nonisolated struct BenchmarkProgress: Equatable, Sendable {
    let completed: Int
    let total: Int
    let lastRun: BenchmarkRunResult?

    var fraction: Double { total > 0 ? Double(completed) / Double(total) : 0 }
}
