import Sapient

/// `MemoryService` backed by SAPIENT's readings: iOS `phys_footprint` (what
/// the per-app memory limit is enforced against) and
/// `os_proc_available_memory`.
nonisolated struct SapientMemoryService: MemoryService {
    func status() -> MemoryStatus {
        MemoryStatus(footprintBytes: memoryFootprintBytes(), availableBytes: availableMemoryBytes())
    }
}
