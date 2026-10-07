import SwiftUI

/// Versions of the app, the engine and the device it runs on.
struct AboutSection: View {
    private let device = DeviceInfo.current()

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "\(version) (\(build))"
    }

    var body: some View {
        Section("About") {
            LabeledContent("App", value: appVersion)
            LabeledContent("SAPIENT engine", value: SapientVersion.current)
            LabeledContent("Device", value: device.model)
            LabeledContent("System", value: device.system)
        }
    }
}
