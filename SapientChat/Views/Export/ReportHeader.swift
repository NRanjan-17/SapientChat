import SwiftUI

/// Title block shared by the PDF reports.
struct ReportHeader: View {
    let title: String
    let subtitle: String
    let device: DeviceInfo
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title.bold())
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("\(device.model) · \(device.system) · \(date.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if device.isSimulator {
                Text("Measured in the iOS Simulator: these numbers reflect the Mac, not a phone.")
                    .font(.subheadline.bold())
                    .foregroundStyle(.orange)
            }
        }
    }
}
