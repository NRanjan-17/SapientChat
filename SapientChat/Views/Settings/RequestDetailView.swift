import SwiftUI
import UIKit

/// Everything saved about one request: what happened, the prompt, the
/// reply, and the raw request and response.
struct RequestDetailView: View {
    let entry: RequestLogEntry

    var body: some View {
        Form {
            Section("Request") {
                LabeledContent("Status") {
                    Text(String(entry.status))
                        .foregroundStyle(entry.status < 400 ? .green : .red)
                }
                LabeledContent("Endpoint", value: "\(entry.method) \(entry.path)")
                LabeledContent("Time", value: entry.date.formatted(date: .abbreviated, time: .standard))
                LabeledContent("From", value: entry.source ?? "Network client")
                if let model = entry.model { LabeledContent("Model", value: model) }
                if let duration = entry.durationMs {
                    LabeledContent("Took", value: Duration.milliseconds(duration).formatted(.units(allowed: [.seconds, .milliseconds], width: .abbreviated)))
                }
                if let error = entry.error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if entry.tokens != nil {
                Section("Speed") {
                    if let tokens = entry.tokens { LabeledContent("Tokens", value: tokens.formatted()) }
                    if let rate = entry.tokensPerSecond { LabeledContent("Generation", value: Format.rate(rate)) }
                    if let ttft = entry.timeToFirstTokenMs { LabeledContent("First token", value: "\(ttft.formatted()) ms") }
                }
            }

            if !entry.messages.isEmpty {
                Section("Prompt") {
                    ForEach(Array(entry.messages.enumerated()), id: \.offset) { _, message in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(message.role.capitalized)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(message.text)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            if let reply = entry.reply {
                Section {
                    Text(reply.isEmpty ? "(empty)" : reply)
                        .textSelection(.enabled)
                } header: {
                    HStack {
                        Text("Reply")
                        Spacer()
                        Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = reply }
                            .labelStyle(.iconOnly)
                    }
                }
            }

            if entry.requestBody != nil || entry.responseBody != nil {
                Section("Raw") {
                    if let body = entry.requestBody {
                        DisclosureGroup("Request body") { raw(body) }
                    }
                    if let body = entry.responseBody {
                        DisclosureGroup("Response body") { raw(body) }
                    }
                }
            }

            if entry.messages.isEmpty && entry.reply == nil && entry.requestBody == nil && entry.responseBody == nil {
                Section {
                    Text("No content saved for this request.")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Prompts, replies and bodies are saved while \"Save prompts and replies\" is on in Endpoints & Access.")
                }
            }
        }
        .navigationTitle(entry.path)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func raw(_ text: String) -> some View {
        Text(text)
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
            }
    }
}
