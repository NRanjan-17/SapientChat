// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// The requests the local API server has answered, newest first, kept
/// across launches. Tap one for its prompt, reply and timing.
struct RequestLogView: View {
    let viewModel: ServerViewModel

    var body: some View {
        List {
            ForEach(viewModel.log) { entry in
                NavigationLink {
                    RequestDetailView(entry: entry)
                } label: {
                    RequestLogRow(entry: entry)
                }
            }
        }
        .overlay {
            if viewModel.log.isEmpty {
                ContentUnavailableView(
                    "No requests yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Requests to the API server show up here.")
                )
            }
        }
        .readableContentWidth(760)
        .navigationTitle("Request Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear", action: viewModel.clearLog)
                    .disabled(viewModel.log.isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack { RequestLogView(viewModel: ChatListViewModel.preview.server) }
}
