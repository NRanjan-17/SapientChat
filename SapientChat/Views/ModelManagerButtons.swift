import SwiftUI

/// A row's one primary action (Get, Resume, Load, Chat, or a stop ring
/// while downloading) plus a ⋯ menu with everything else.
struct ModelManagerButtons: View {
    let row: ModelManagerViewModel.Row
    let actions: ModelManagerRow.Actions

    var body: some View {
        HStack(spacing: 6) {
            primary
            Menu {
                ModelManagerMenuItems(row: row, actions: actions)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: .circle)
            }
            .accessibilityLabel("More for \(row.model.displayName)")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder private var primary: some View {
        switch row.activity {
        case .downloading(let progress):
            DownloadRing(fraction: progress.fraction, tint: row.model.tint) { actions.cancel(row) }
        case .loading:
            ProgressView()
                .frame(width: 30, height: 30)
        case nil:
            if row.isLoaded {
                PillButton("Chat", tint: .accentColor, filled: true) { actions.startChat(row) }
            } else if row.download.isDownloaded {
                PillButton("Load", tint: row.model.tint) { actions.load(row) }
                    .disabled(!row.fits)
            } else if row.fits {
                PillButton(row.download.bytes > 0 ? "Resume" : "Get", tint: row.model.tint) { actions.download(row) }
            }
        }
    }
}

/// Every action that fits the row's state, for the ⋯ menu and long press.
struct ModelManagerMenuItems: View {
    let row: ModelManagerViewModel.Row
    let actions: ModelManagerRow.Actions

    var body: some View {
        if row.activity != nil {
            Button("Cancel", systemImage: "xmark.circle") { actions.cancel(row) }
                .disabled(row.activity == .loading)
        } else {
            Button("New Chat", systemImage: "square.and.pencil") { actions.startChat(row) }
                .disabled(!row.fits)
            if row.isLoaded {
                Button("Unload from Memory", systemImage: "eject") { actions.unload(row) }
            } else {
                Button("Load into Memory", systemImage: "memorychip") { actions.load(row) }
                    .disabled(!row.fits)
            }
            if !row.download.isDownloaded {
                Button(row.download.bytes > 0 ? "Resume Download" : "Download", systemImage: "arrow.down.circle") {
                    actions.download(row)
                }
            }
            if ContextWindowStore.isAdjustable(row.model) {
                Button("Context Window…", systemImage: "text.alignleft") { actions.contextWindow(row) }
                    .disabled(row.activity != nil)
            }
            if row.canDelete {
                Divider()
                Button("Delete Download", systemImage: "trash", role: .destructive) { actions.delete(row) }
            }
        }
    }
}

/// A compact App Store-style capsule button.
struct PillButton: View {
    let title: String
    let tint: Color
    var filled = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, tint: Color, filled: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.tint = tint
        self.filled = filled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(filled ? .white : tint)
                .padding(.horizontal, 14)
                .frame(height: 30)
                .background(filled ? AnyShapeStyle(tint.gradient) : AnyShapeStyle(tint.opacity(0.15)), in: .capsule)
                .opacity(isEnabled ? 1 : 0.4)
        }
    }
}

/// Download progress as a ring with a stop square; tapping cancels.
struct DownloadRing: View {
    let fraction: Double?
    let tint: Color
    let onCancel: () -> Void

    var body: some View {
        Button(action: onCancel) {
            ZStack {
                Circle()
                    .stroke(tint.opacity(0.2), lineWidth: 3)
                if let fraction {
                    Circle()
                        .trim(from: 0, to: max(0.02, fraction))
                        .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth, value: fraction)
                } else {
                    ProgressView()
                        .controlSize(.mini)
                }
                RoundedRectangle(cornerRadius: 2)
                    .fill(tint)
                    .frame(width: 9, height: 9)
            }
            .frame(width: 30, height: 30)
        }
        .accessibilityLabel("Stop download")
    }
}
