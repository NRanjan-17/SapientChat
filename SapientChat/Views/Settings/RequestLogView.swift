// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI

/// The requests the local API server has answered, newest first, kept
/// across launches. Search and filter them, tap one for its prompt, reply
/// and timing, open one in the Playground to send it again, or export them.
struct RequestLogView: View {
    let viewModel: ServerViewModel
    /// Opens a request in the Playground.
    var onReplay: (RequestLogEntry) -> Void = { _ in }
    @State private var filter = RequestLogFilter()
    @State private var isConfirmingClear = false

    private var entries: [RequestLogEntry] { filter.apply(viewModel.log) }

    var body: some View {
        List {
            ForEach(entries) { entry in
                NavigationLink {
                    RequestDetailView(entry: entry, onReplay: onReplay)
                } label: {
                    RequestLogRow(entry: entry)
                }
                .swipeActions(edge: .leading) {
                    if entry.canReplay {
                        Button("Replay", systemImage: "arrow.clockwise") { onReplay(entry) }
                            .tint(.accentColor)
                    }
                }
            }
        }
        .overlay {
            if viewModel.log.isEmpty {
                ContentUnavailableView(
                    "No requests yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Requests to the API server and from the Playground show up here.")
                )
            } else if entries.isEmpty {
                ContentUnavailableView.search
            }
        }
        .searchable(text: $filter.text, prompt: "Path, model, app or text")
        .readableContentWidth(760)
        .navigationTitle("Request Log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Errors Only", systemImage: "exclamationmark.triangle", isOn: $filter.errorsOnly)
                    Picker("App", selection: $filter.source) {
                        Text("All Apps").tag(String?.none)
                        ForEach(RequestLogFilter.sources(in: viewModel.log), id: \.self) { source in
                            Text(source).tag(String?.some(source))
                        }
                    }
                    Divider()
                    ShareLink(
                        item: RequestLogFilter.export(entries),
                        preview: SharePreview("Sapient request log (\(entries.count))")
                    ) {
                        Label("Export \(entries.count) as JSON", systemImage: "square.and.arrow.up")
                    }
                    .disabled(entries.isEmpty)
                    Button("Clear Log", systemImage: "trash", role: .destructive) { isConfirmingClear = true }
                        .disabled(viewModel.log.isEmpty)
                } label: {
                    Label("Filter and Export", systemImage: filter.isActive
                        ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .alert("Clear the request log?", isPresented: $isConfirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: viewModel.clearLog)
        } message: {
            Text("All \(viewModel.log.count) saved requests are removed from this device.")
        }
    }
}

#Preview {
    NavigationStack { RequestLogView(viewModel: ChatListViewModel.preview.server) }
}
