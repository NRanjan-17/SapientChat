// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import SwiftUI
import UIKit

extension AppProblem {
    /// `from(_:)` with what the device knows now: whether it's offline, and
    /// whether it's an iPhone or iPad (for storage advice).
    static func current(_ error: any Error, model: String, progress: DownloadProgress? = nil) -> AppProblem {
        from(error, model: model, progress: progress, isOffline: NetworkMonitor.shared.isOffline, device: UIDevice.current.model)
    }
}

extension View {
    /// A centered pop-up for `problem`: what happened, what to do, and a
    /// Try Again (or Resume) button when trying again can work.
    func problemAlert(_ problem: Binding<AppProblem?>, onRetry: ((AppProblem) -> Void)? = nil) -> some View {
        alert(
            problem.wrappedValue?.title ?? "",
            isPresented: Binding(get: { problem.wrappedValue != nil }, set: { if !$0 { problem.wrappedValue = nil } }),
            presenting: problem.wrappedValue
        ) { shown in
            if shown.canRetry, let onRetry {
                Button(shown.retryTitle) { onRetry(shown) }
            }
            if let details = shown.details {
                Button("Copy Details") { UIPasteboard.general.string = details }
            }
            Button("OK", role: .cancel) {}
        } message: { shown in
            Text(shown.message)
        }
    }
}
