// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

//
//  SapientStudioApp.swift
//  SapientStudio
//
//  Created by Nalinish Ranjan on 02/10/26.
//

import SwiftData
import SwiftUI

@main
struct SapientStudioApp: App {
    private let container: ModelContainer
    @State private var viewModel: ChatListViewModel
    /// The animated SAPIENT splash, once per launch.
    @State private var showsSplash = true
    /// The Terms of Service haven't been accepted on this device yet.
    @State private var needsTerms = !TermsOfService.isAccepted()

    init() {
        // Chats are stored on this device only (no CloudKit).
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Conversation.self, StoredMessage.self, RequestRecord.self, BenchmarkRecord.self, PromptSetRecord.self)
        } catch {
            fatalError("Couldn't open the chat database: \(error)")
        }
        self.container = container
        // In front of the real Island: it also keeps the current activity
        // for `GET /v1/activity`, which the Mac's notch helper (Sapient
        // Island) reads, since a Mac has no Dynamic Island of its own.
        let activities = WindowIsland(inner: ActivityKitLiveActivities())
        var services = AppServices.live()
        services.liveActivities = activities
        // Registers the background task handler, which iOS wants at launch.
        services.downloadCoordinator.background = ContinuedProcessingDownloads()
        _viewModel = State(initialValue: ChatListViewModel(
            services: services,
            store: SwiftDataConversationStore(context: container.mainContext),
            liveActivities: activities,
            requestLog: SwiftDataRequestLogStore(context: container.mainContext),
            benchmarkHistory: SwiftDataBenchmarkHistoryStore(context: container.mainContext),
            promptSets: SwiftDataPromptSetStore(context: container.mainContext)
        ))
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootView(viewModel: viewModel)
                if showsSplash {
                    SplashView { showsSplash = false }
                }
            }
            // Over everything until accepted; it can't be swiped away.
            .fullScreenCover(isPresented: $needsTerms) {
                TermsOfServiceView {
                    TermsOfService.accept()
                    needsTerms = false
                }
            }
        }
        .modelContainer(container)
        .commands { AppCommands(viewModel: viewModel) }
    }
}
