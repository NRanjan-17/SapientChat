/// The Benchmark tab's two modes.
nonisolated enum BenchmarkMode: String, CaseIterable, Sendable {
    case single
    case compare

    var title: String {
        switch self {
        case .single: "Single Model"
        case .compare: "Compare"
        }
    }
}
