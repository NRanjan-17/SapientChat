import SwiftUI

/// Memory and heat on this device, and which models are loaded.
struct ModelStatsDeviceSection: View {
    let device: DeviceStatus
    let loadedModels: [String]

    var body: some View {
        Section("Device") {
            if let used = device.memory.footprintBytes {
                LabeledContent("App memory in use", value: Format.bytes(used))
            }
            if let available = device.memory.availableBytes {
                LabeledContent("iOS still allows", value: Format.bytes(available))
            }
            LabeledContent("Thermal state", value: device.thermal.label ?? "Normal")
            LabeledContent("Loaded models", value: loadedModels.isEmpty ? "None" : loadedModels.joined(separator: ", "))
        }
    }
}
