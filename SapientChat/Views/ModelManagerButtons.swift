import SwiftUI

/// The actions a manager row offers for its current state.
struct ModelManagerButtons: View {
    let row: ModelManagerViewModel.Row
    let actions: ModelManagerRow.Actions

    var body: some View {
        HStack {
            if row.activity != nil {
                Button("Cancel", systemImage: "xmark.circle") { actions.cancel(row) }
                    .disabled(row.activity == .loading)
            } else if row.isLoaded {
                Button("New Chat", systemImage: "square.and.pencil") { actions.startChat(row) }
                    .buttonStyle(.borderedProminent)
                Button("Unload", systemImage: "eject") { actions.unload(row) }
            } else {
                if !row.download.isDownloaded {
                    Button(row.download.bytes > 0 ? "Resume" : "Download", systemImage: "arrow.down.circle") {
                        actions.download(row)
                    }
                }
                Button("Load", systemImage: "memorychip") { actions.load(row) }
                    .disabled(!row.fits)
                Button("New Chat", systemImage: "square.and.pencil") { actions.startChat(row) }
                    .disabled(!row.fits)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .labelStyle(.titleAndIcon)
        .font(.subheadline)
        // Several buttons in one List row: keep taps on the buttons only.
        .buttonBorderShape(.capsule)
    }
}
