import SwiftUI

/// One answered request: status code, method and path, time.
struct RequestLogRow: View {
    let entry: ServeRouter.LogEntry

    var body: some View {
        HStack {
            Text(String(entry.status))
                .font(.callout.monospaced())
                .foregroundStyle(entry.status < 400 ? .green : .red)
            Text("\(entry.method) \(entry.path)")
                .font(.callout.monospaced())
                .lineLimit(1)
            Spacer()
            Text(entry.date, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
