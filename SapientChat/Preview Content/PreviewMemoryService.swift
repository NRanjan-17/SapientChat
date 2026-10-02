/// `MemoryService` for SwiftUI previews: fixed readings.
nonisolated struct PreviewMemoryService: MemoryService {
    var memory = MemoryStatus(footprintBytes: 900_000_000, availableBytes: 2_400_000_000)

    func status() -> MemoryStatus {
        memory
    }
}
