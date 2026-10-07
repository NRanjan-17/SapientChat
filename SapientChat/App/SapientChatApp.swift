//
//  SapientChatApp.swift
//  SapientChat
//
//  Created by Nalinish Ranjan on 02/10/26.
//

import SwiftData
import SwiftUI

@main
struct SapientChatApp: App {
    private let container: ModelContainer
    @State private var viewModel: ChatListViewModel

    init() {
        // Chats are stored on this device only (no CloudKit).
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Conversation.self, StoredMessage.self)
        } catch {
            fatalError("Couldn't open the chat database: \(error)")
        }
        self.container = container
        _viewModel = State(initialValue: ChatListViewModel(
            services: .live(),
            store: SwiftDataConversationStore(context: container.mainContext),
            liveActivities: ActivityKitLiveActivities()
        ))
    }

    var body: some Scene {
        WindowGroup {
            RootView(viewModel: viewModel)
        }
        .modelContainer(container)
    }
}
