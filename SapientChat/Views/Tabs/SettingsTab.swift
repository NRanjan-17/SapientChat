// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// App-wide settings: the on-device API server and information about the
/// engine and device.
struct SettingsTab: View {
    @Bindable var server: ServerViewModel
    /// Releases loaded models, so they reload on the new Compute choice.
    var onComputeChange: () -> Void = {}
    @AppStorage(AppSettings.showReplyStats) private var showReplyStats = true
    @AppStorage(EngineBackendPreference.computeKey) private var compute = ComputePreference.automatic

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
                    Picker("Compute", systemImage: "cpu", selection: $compute) {
                        ForEach(ComputePreference.allCases, id: \.self) { compute in
                            Text(compute.title).tag(compute)
                        }
                    }
                    .onChange(of: compute) { onComputeChange() }
                } header: {
                    Text("Engine")
                } footer: {
                    Text(computeFooter)
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

    private var computeFooter: String {
        let what = switch compute {
        case .automatic:
            "CPU + GPU: the GPU reads your prompt, the CPU writes the reply. While the phone is hot or in Low Power Mode, the GPU alone, so it runs cooler."
        case .hybrid: "The GPU reads your prompt, the CPU writes the reply."
        case .gpu: "Everything on the GPU."
        case .cpu: "Everything on the CPU."
        }
        return what + " Models in memory reload when you change this. While the API server runs in the background, models use the CPU (iOS allows no GPU work there)."
    }
}

#Preview {
    SettingsTab(server: ChatListViewModel.preview.server)
}
