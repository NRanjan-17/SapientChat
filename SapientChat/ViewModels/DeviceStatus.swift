import Foundation
import Observation

/// App-wide device state shared by every screen: memory as iOS sees it and
/// the thermal state (which is also fed to the engine).
@Observable
final class DeviceStatus {
    private(set) var memory: MemoryStatus
    private(set) var thermal: ThermalPressure = .nominal

    @ObservationIgnored private let memoryService: any MemoryService
    @ObservationIgnored private let thermalService: any ThermalService

    init(memoryService: any MemoryService, thermalService: any ThermalService) {
        self.memoryService = memoryService
        self.thermalService = thermalService
        memory = memoryService.status()
    }

    func refreshMemory() {
        memory = memoryService.status()
    }

    /// Mirrors the thermal state until the calling task is cancelled.
    func observeThermal() async {
        for await pressure in thermalService.pressureUpdates() {
            thermal = pressure
        }
    }

    /// Why `model` can't be loaded right now, or nil if it should fit. The
    /// model currently loaded is released first, so its memory counts as free.
    func memoryProblem(loading model: PhoneModel?, chat: any ChatService) async -> String? {
        guard let model else { return nil }
        let somethingLoaded = await chat.loadedModel() != nil
        refreshMemory()
        let reclaimable = somethingLoaded ? memory.footprintBytes ?? 0 : 0
        return model.fitProblem(availableBytes: memory.availableBytes, reclaimableBytes: reclaimable)
    }
}
