import SwiftUI

/// App-wide settings: the on-device API server and information about the
/// engine and device.
struct SettingsTab: View {
    @Bindable var server: ServerViewModel
    @AppStorage(AppSettings.showReplyStats) private var showReplyStats = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Show reply stats", systemImage: "gauge.with.dots.needle.33percent", isOn: $showReplyStats)
                } header: {
                    Text("Chat")
                } footer: {
                    Text("Speed and timing under each reply. The chart button in a chat shows more.")
                }

                Section {
                    Toggle(isOn: $server.isOn) {
                        Label(server.statusTitle, systemImage: "network")
                    }
                    .tint(.green)
                    if case .failed(let message) = server.status {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    NavigationLink {
                        ServerView(viewModel: server)
                    } label: {
                        Label("Endpoints & Access", systemImage: "link")
                    }
                    NavigationLink {
                        RequestLogView(viewModel: server)
                    } label: {
                        LabeledContent {
                            Text(server.log.count, format: .number)
                        } label: {
                            Label("Request Log", systemImage: "list.bullet.rectangle")
                        }
                    }
                } header: {
                    Text("API Server")
                } footer: {
                    Text("Serves SAPIENT's OpenAI-compatible API from the models on this device while the app is open.")
                }

                AboutSection()
            }
            .readableContentWidth(720)
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsTab(server: ChatListViewModel.preview.server)
}
