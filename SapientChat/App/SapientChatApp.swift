//
//  SapientChatApp.swift
//  SapientChat
//
//  Created by Nalinish Ranjan on 02/10/26.
//

import SwiftUI

@main
struct SapientChatApp: App {
    @State private var viewModel = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ChatView(viewModel: viewModel)
        }
    }
}
