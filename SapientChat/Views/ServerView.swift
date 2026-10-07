import SwiftUI
import UIKit

/// The local SAPIENT API server's details, pushed from Settings: on/off,
/// background mode, the URLs to call it at, access settings and Try It commands.
/// The request log has its own page (`RequestLogView`).
struct ServerView: View {
    @Bindable var viewModel: ServerViewModel
    @State private var portText = ""
    @State private var isConfirmingBackground = false

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
                    + "Apps on this iPhone reach SapientChat through a sapient:// handoff instead (SapientKit does both).")
            }

            Section {
                if ServerViewModel.canRunInBackground {
                    Toggle("Keep running in background", isOn: runsInBackground)
                }
                if let error = viewModel.backgroundError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Background")
            } footer: {
                Text(backgroundFooter)
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

            TryItSections(viewModel: viewModel)
        }
        .alert("Keep Running in Background?", isPresented: $isConfirmingBackground) {
            Button("Turn On") { viewModel.setRunsInBackground(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("SapientChat keeps running with the app closed to answer API requests. "
                + "This uses noticeably more battery and can warm the phone. "
                + "Models run on the CPU (iOS doesn't allow GPU work in the background), so models in memory are released now. "
                + "iOS may still close the app if memory runs low. Not available in App Store builds.")
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

    /// Turning on asks first (battery); turning off doesn't.
    private var runsInBackground: Binding<Bool> {
        Binding { viewModel.runsInBackground } set: { on in
            if on { isConfirmingBackground = true } else { viewModel.setRunsInBackground(false) }
        }
    }

    private var backgroundFooter: String {
        if viewModel.runsInBackground {
            return "Running with the app closed, on the CPU. Uses more battery; turn off when you don't need it."
        }
        return "With the app closed, requests already running get about 30 seconds to finish, then the server pauses "
            + "until you open SapientChat again."
            + (ServerViewModel.canRunInBackground ? " Turn this on to keep serving with the app closed." : "")
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
