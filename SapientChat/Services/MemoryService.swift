/// Reads the app's memory as the OS sees it.
nonisolated protocol MemoryService: Sendable {
    func status() -> MemoryStatus
}
