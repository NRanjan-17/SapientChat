import SwiftUI
import UIKit

/// Turns on the local SAPIENT API server, shows the URLs to call it at,
/// and logs the requests it answers.
struct ServerView: View {
    @Bindable var viewModel: ServerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var portText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(isOn: $viewModel.isOn) {
                        Label(statusTitle, systemImage: statusImage)
                            .foregroundStyle(statusColor)
                    }
                    if case .failed(let message) = viewModel.status {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Serves SAPIENT's OpenAI-compatible API (as `sapient serve` does) from the models on this device. "
                        + "It runs while SapientChat is open; iOS pauses it in the background. "
                        + "Apps on this iPhone reach SapientChat through a sapient:// handoff instead (SapientKit does both).")
                }

                Section("Endpoints") {
                    ForEach(viewModel.endpoints, id: \.url) { endpoint in
                        LabeledContent(endpoint.label) {
                            Text(endpoint.url)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        .contextMenu {
                            Button("Copy", systemImage: "doc.on.doc") { UIPasteboard.general.string = endpoint.url }
                        }
                    }
                    if viewModel.allowsNetwork && viewModel.addresses.isEmpty {
                        Text("Join Wi-Fi or turn on Personal Hotspot to reach this device from others.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    LabeledContent("Port") {
                        TextField("Port", text: $portText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .onSubmit(applyPort)
                    }
                    Toggle("Allow other devices", isOn: $viewModel.allowsNetwork)
                    LabeledContent("API key") {
                        SecureField("None", text: $viewModel.apiKey)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    Toggle("Keep screen awake", isOn: $viewModel.keepsAwake)
                } header: {
                    Text("Settings")
                } footer: {
                    Text("With an API key set, clients must send `Authorization: Bearer <key>`. "
                        + "Set one before allowing other devices on a shared network.")
                }

                Section("Try it") {
                    Text(exampleCommand)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button("Copy Command", systemImage: "doc.on.doc") { UIPasteboard.general.string = exampleCommand }
                }

                Section {
                    if viewModel.log.isEmpty {
                        Text("No requests yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(viewModel.log) { entry in
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
                    }
                } header: {
                    HStack {
                        Text("Requests")
                        Spacer()
                        if !viewModel.log.isEmpty {
                            Button("Clear", action: viewModel.clearLog)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("API Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                portText = String(viewModel.port)
                viewModel.refreshAddresses()
            }
            .onDisappear(perform: applyPort)
        }
    }

    private var statusTitle: String {
        switch viewModel.status {
        case .stopped: "Server off"
        case .starting: "Starting…"
        case .running: "Running"
        case .failed: "Couldn't start"
        }
    }

    private var statusImage: String {
        switch viewModel.status {
        case .running: "dot.radiowaves.left.and.right"
        case .failed: "exclamationmark.triangle"
        default: "antenna.radiowaves.left.and.right.slash"
        }
    }

    private var statusColor: Color {
        switch viewModel.status {
        case .running: .green
        case .failed: .red
        default: .primary
        }
    }

    private var exampleCommand: String {
        let base = viewModel.endpoints.last?.url ?? "http://127.0.0.1:\(viewModel.port)"
        let auth = viewModel.apiKey.isEmpty ? "" : " -H 'Authorization: Bearer \(viewModel.apiKey)'"
        return """
        curl \(base)/v1/chat/completions\(auth) -H 'Content-Type: application/json' \
        -d '{"model":"\(PhoneModel.defaultAlias)","messages":[{"role":"user","content":"Hi!"}]}'
        """
    }

    private func applyPort() {
        if let port = UInt16(portText), port > 0, port != viewModel.port {
            viewModel.port = port
        } else {
            portText = String(viewModel.port)
        }
    }
}

#Preview {
    ServerView(viewModel: ChatListViewModel.preview.server)
}
