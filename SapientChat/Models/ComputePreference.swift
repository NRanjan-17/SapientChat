import Foundation

/// Where models run. Automatic prefers CPU + GPU (the GPU reads the prompt,
/// the CPU writes the reply) and uses the GPU alone while the phone is hot
/// or in Low Power Mode, where the CPU half adds heat and drain. On Apple
/// chips the two share memory and iOS memory-maps 4/8-bit GGUF models, so
/// for those CPU + GPU needs about as much memory as the GPU alone; a
/// full-precision model would be held twice, so Automatic uses the GPU.
nonisolated enum ComputePreference: String, CaseIterable, Sendable, Codable {
    case automatic
    case hybrid
    case gpu
    case cpu

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .hybrid: "CPU + GPU"
        case .gpu: "GPU"
        case .cpu: "CPU"
        }
    }

    /// Below this much RAM, Automatic keeps to the GPU alone: CPU + GPU's
    /// extra working memory pushed a 4 GB iPad into an iOS memory kill.
    static let hybridMinimumMemory: UInt64 = 6 * 1024 * 1024 * 1024

    /// The engine's backend for this choice right now. Automatic uses CPU +
    /// GPU only where it costs about one copy of the model (memory-mapped
    /// GGUF) on a device with room to spare, and the GPU alone when the
    /// device is hot or in Low Power Mode.
    func backend(
        thermal: ProcessInfo.ThermalState,
        lowPower: Bool,
        isMemoryMapped: Bool = true,
        physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory
    ) -> String {
        switch self {
        case .hybrid: return "hybrid"
        case .gpu: return "wgpu"
        case .cpu: return "cpu"
        case .automatic:
            let underLoad = thermal == .serious || thermal == .critical || lowPower
            let roomForBoth = isMemoryMapped && physicalMemory >= Self.hybridMinimumMemory
            return !underLoad && roomForBoth ? "hybrid" : "wgpu"
        }
    }
}
