/// The app's memory as the OS sees it.
nonisolated struct MemoryStatus: Equatable, Sendable {
    /// Current footprint: the number iOS compares against the app's limit.
    var footprintBytes: UInt64?
    /// Bytes the app can still allocate before iOS steps in. Nil when the
    /// platform enforces no limit (e.g. the simulator).
    var availableBytes: UInt64?

    static let unknown = MemoryStatus(footprintBytes: nil, availableBytes: nil)
}
