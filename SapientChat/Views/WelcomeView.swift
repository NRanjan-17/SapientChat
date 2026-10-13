// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// What the wide layout (iPad, Mac) shows beside the chat list when no chat
/// is open: the app's name and one card per thing you can do, each with its
/// current state.
struct WelcomeView: View {
    let viewModel: ChatListViewModel

    /// SAPIENT blue, as on the app icon.
    static let brand = Color(red: 0x2A / 255, green: 0x7D / 255, blue: 1)

    private var models: ModelManagerViewModel { viewModel.models }
    private var server: ServerViewModel { viewModel.server }

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image(.logoSapient)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white)
                        .padding(16)
                        .frame(width: 76, height: 76)
                        .background(
                            LinearGradient(
                                colors: [Self.brand, Color(red: 0x05 / 255, green: 0x62 / 255, blue: 0xEF / 255)],
                                startPoint: .top, endPoint: .bottom
                            ),
                            in: .rect(cornerRadius: 20)
                        )
                        .shadow(color: Self.brand.opacity(0.35), radius: 16, y: 8)
                        .accessibilityHidden(true)
                    Text("Sapient Studio")
                        .font(.largeTitle.bold())
                    Text("Run, test and serve language models on this \(UIDevice.current.spokenName). Nothing you type leaves it.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 36)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                    WelcomeCard(
                        title: "New Chat", symbol: "square.and.pencil",
                        detail: "Talk to \(displayName(of: viewModel.modelForNewChat))", action: viewModel.newChat
                    )
                    WelcomeCard(
                        title: "Playground", symbol: AppTab.playground.symbol,
                        detail: "Build, run and copy API requests"
                    ) { viewModel.selectedTab = .playground }
                    WelcomeCard(title: "Models", symbol: AppTab.models.symbol, detail: modelsDetail) {
                        viewModel.selectedTab = .models
                    }
                    WelcomeCard(
                        title: "API Server", symbol: "network", detail: serverDetail,
                        isOn: server.status == .running
                    ) { viewModel.selectedTab = .settings }
                    WelcomeCard(
                        title: "Benchmark", symbol: AppTab.benchmark.symbol,
                        detail: "Speed, comparisons, prompt sets"
                    ) { viewModel.selectedTab = .benchmark }
                }
                .frame(maxWidth: 820)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .task { await models.refresh() }
    }

    private func displayName(of alias: String) -> String {
        alias.split(separator: "/").last.map(String.init) ?? alias
    }

    private var modelsDetail: String {
        let downloaded = models.rows.count { $0.download.isDownloaded }
        let loaded = models.loaded.count
        if models.rows.isEmpty { return "Download and manage models" }
        if downloaded == 0 { return "None downloaded yet · \(models.rows.count) available" }
        return "\(downloaded) downloaded · \(loaded) in memory"
    }

    private var serverDetail: String {
        switch server.status {
        case .running: "Running at \(server.endpoints.last?.url.replacing("http://", with: "") ?? "port \(server.port)")"
        case .starting: "Starting…"
        case .failed: "Couldn't start"
        case .stopped: "Off · for other apps and devices"
        }
    }
}

/// One thing to do, with where it stands.
private struct WelcomeCard: View {
    let title: String
    let symbol: String
    let detail: String
    /// A live dot beside the title (the server, when it's running).
    var isOn = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 42, height: 42)
                    .background(.tint.opacity(0.16), in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.headline)
                        if isOn {
                            Circle()
                                .fill(.tint)
                                .frame(width: 7, height: 7)
                                .accessibilityLabel("On")
                        }
                    }
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            // One height for every card, whatever its text wraps to.
            .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88, alignment: .leading)
            .contentShape(.rect(cornerRadius: 18))
            .glassSurface(in: .rect(cornerRadius: 18), interactive: true)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WelcomeView(viewModel: .preview)
}
