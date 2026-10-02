/// One model's side of a comparison: its answer and its benchmark.
nonisolated struct ModelComparison: Identifiable, Equatable, Sendable {
    let model: String
    var answer: String
    var benchmark: BenchmarkResult?

    var id: String { model }

    /// Highest footprint seen during this model's benchmark runs. Unlike the
    /// process peak, it isn't inflated by a model that ran earlier.
    var memoryInUseBytes: UInt64? {
        benchmark.flatMap { result in
            (result.warmupRuns + result.runs).compactMap(\.footprintBytes).max()
        }
    }
}
