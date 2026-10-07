import SwiftUI

/// One answered request: status, method and path, model, the prompt's
/// first line, when, and the speed for generations.
struct RequestLogRow: View {
    let entry: RequestLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(String(entry.status))
                    .font(.callout.monospaced().weight(.semibold))
                    .foregroundStyle(entry.status < 400 ? .green : .red)
                Text("\(entry.method) \(entry.path)")
                    .font(.callout.monospaced())
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(entry.date, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let prompt = entry.promptPreview {
                Text(prompt)
                    .font(.subheadline)
                    .lineLimit(1)
            } else if let error = entry.error {
                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }
            if !details.isEmpty {
                Text(details.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private var details: [String] {
        var parts: [String] = []
        if let model = entry.model { parts.append(model.split(separator: "/").last.map(String.init) ?? model) }
        if let rate = entry.tokensPerSecond { parts.append(Format.rate(rate)) }
        if let source = entry.source { parts.append("from \(source)") }
        return parts
    }
}
