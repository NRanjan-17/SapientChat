import SwiftUI

/// What's in memory now: loaded models (of four slots), memory used, and
/// what iOS still allows.
struct MemorySummarySection: View {
    let loaded: [String]
    let capacity: Int
    let memory: MemoryStatus

    var body: some View {
        Section {
            LabeledContent("Loaded models", value: "\(loaded.count) of \(capacity)")
            if let used = memory.footprintBytes {
                LabeledContent("App memory in use", value: Format.bytes(used))
            }
            if let available = memory.availableBytes {
                LabeledContent("iOS still allows", value: Format.bytes(available))
            }
        } header: {
            Text("Memory")
        } footer: {
            Text("Up to \(capacity) models stay loaded, so switching between their chats is instant. Loading another releases the one used least recently.")
        }
    }
}
