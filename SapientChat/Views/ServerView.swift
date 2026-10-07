import SwiftUI
import UIKit

/// The local SAPIENT API server's details, pushed from Settings: on/off,
/// the URLs to call it at, access settings and a ready-to-paste command.
/// The request log has its own page (`RequestLogView`).
struct ServerView: View {
    @Bindable var viewModel: ServerViewModel
    @State private var portText = ""

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $viewModel.isOn) {
                    Label(viewModel.statusTitle, systemImage: statusImage)
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
        }
        .navigationTitle("Endpoints & Access")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            portText = String(viewModel.port)
            viewModel.refreshAddresses()
        }
        .onDisappear(perform: applyPort)
    }


    private var statusImage: String {
        switch viewModel.status {
        case .running: "network"
        case .failed: "exclamationmark.triangle"
        default: "power"
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
    NavigationStack { ServerView(viewModel: ChatListViewModel.preview.server) }
}
