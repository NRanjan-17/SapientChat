// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// App-wide settings: the on-device API server and information about the
/// engine and device.
struct SettingsTab: View {
    @Bindable var server: ServerViewModel
    /// Releases loaded models, so they reload on the new Compute choice.
    var onComputeChange: () -> Void = {}
    /// Opens a logged request in the Playground.
    var onReplay: (RequestLogEntry) -> Void = { _ in }
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
                        RequestLogView(viewModel: server, onReplay: onReplay)
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
            .scrollEdgeEffectStyle(.hard, for: .bottom)
            .navigationTitle("Settings")
            // The same title row as Chats and Benchmark.
            .toolbarTitleDisplayMode(.inlineLarge)
            .pageTitle("Settings", columnWidth: 720)
        }
    }

    private var computeFooter: String {
        let what = switch compute {
        case .automatic:
            "Picks the fastest option, and a cooler one while the device is hot or in Low Power Mode."
        case .hybrid: "The GPU reads your prompt, the CPU writes the reply."
        case .gpu: "Everything on the GPU."
        case .cpu: "Everything on the CPU."
        }
        return what + " Changing this reloads models in memory."
    }
}

#Preview {
    SettingsTab(server: ChatListViewModel.preview.server)
}
