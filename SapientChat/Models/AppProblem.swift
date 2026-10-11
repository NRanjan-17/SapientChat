// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Something that stopped a model from downloading, loading or answering,
/// as the person using the app should see it: what happened and what to do
/// next. Built from the engine's error text, which is written for
/// developers ("Load(reason: \"…dns error: failed to lookup address…\")").
nonisolated struct AppProblem: Equatable, Sendable, Identifiable {
    enum Kind: String, Sendable {
        case noNetwork
        case hubUnreachable
        case hubError
        case rateLimited
        case accessDenied
        case notFound
        case storageFull
        case interrupted
        case downloadFailed
        /// Won't fit even with every idle model released.
        case notEnoughMemory
        /// Would fit, but only by releasing a model that's answering now.
        case memoryBusy
        /// The app was closed by iOS while loading the model last time.
        case closedWhileLoading
        /// A loaded model was released before it could answer.
        case modelReleased
        case loadFailed
    }

    let kind: Kind
    let title: String
    let message: String
    /// The engine's own text, for "Copy Details" and bug reports.
    var details: String?

    var id: String { "\(kind.rawValue)|\(title)|\(message)" }

    /// Trying the same thing again can work (it can't for a gated or
    /// missing model).
    var canRetry: Bool {
        kind != .accessDenied && kind != .notFound
    }

    /// "Resume" when the download keeps what it has, else "Try Again".
    var retryTitle: String {
        kind == .storageFull || kind == .interrupted ? "Resume" : "Try Again"
    }

    /// A stable code for API clients, e.g. "no_network".
    var code: String {
        kind.rawValue.replacing(/[A-Z]/) { "_" + $0.output.lowercased() }
    }

    /// One line for places with no room for both: "You're Offline. Connect…".
    var summary: String { "\(title). \(message)" }

    // MARK: Building

    /// What went wrong getting `model` ready (download, then load).
    /// - Parameters:
    ///   - progress: how far the download got, if it started.
    ///   - isOffline: the device has no network path right now, which beats
    ///     guessing from the error text.
    ///   - device: "iPhone" or "iPad", for storage advice.
    static func from(
        _ error: any Error,
        model: String,
        progress: DownloadProgress? = nil,
        isOffline: Bool = false,
        device: String = "iPhone"
    ) -> AppProblem {
        if let problem = error as? AppProblem { return problem }
        if case ChatViewModelError.wontFit(let message) = error {
            return AppProblem(kind: .notEnoughMemory, title: "Not Enough Memory", message: message)
        }
        if case ChatViewModelError.busy(let message) = error {
            return AppProblem(kind: .memoryBusy, title: "Memory Is in Use", message: message)
        }
        if case ChatServiceError.noModelLoaded = error {
            return AppProblem(
                kind: .modelReleased, title: "Model Was Released",
                message: "\(model) was released to make room for another model before it could answer. Tap Try Again to load it again."
            )
        }
        let details = String(describing: error)
        return classify(details, model: model, progress: progress, isOffline: isOffline, device: device)
    }

    /// Sorts the engine's text into a cause. Pure, so the real messages the
    /// engine prints are unit-tested against it.
    static func classify(
        _ text: String,
        model: String,
        progress: DownloadProgress? = nil,
        isOffline: Bool = false,
        device: String = "iPhone"
    ) -> AppProblem {
        let lower = text.lowercased()
        let isDownload = lower.contains("failed to download") || lower.contains("huggingface") || lower.contains("hugging face")
        let soFar = progress.flatMap { $0.downloadedBytes > 0 ? " at \($0.text)" : nil } ?? ""

        func has(_ needles: String...) -> Bool { needles.contains { lower.contains($0) } }
        func problem(_ kind: Kind, _ title: String, _ message: String) -> AppProblem {
            AppProblem(kind: kind, title: title, message: message, details: text)
        }

        if has("no space left", "os error 28") {
            let need = progress.flatMap { $0.totalBytes > $0.downloadedBytes ? " (\(Format.bytes($0.totalBytes - $0.downloadedBytes)) more needed)" : nil } ?? ""
            return problem(.storageFull, "Not Enough Storage",
                           "Your \(device) ran out of space while downloading \(model)\(need). Delete models you don't use in Models, or free up space in Settings › General › \(device) Storage, then tap Resume. What's downloaded so far is kept.")
        }
        if isOffline || has("dns error", "failed to lookup address", "network is unreachable", "os error 50", "os error 51",
                            "not connected to the internet", "internet connection appears to be offline") {
            return problem(.noNetwork, "You're Offline",
                           "Downloading \(model) needs an internet connection. Connect to Wi-Fi or turn on mobile data, then tap Try Again. Models you've already downloaded still work offline.")
        }
        if has("429", "too many requests") {
            return problem(.rateLimited, "Too Many Downloads Right Now",
                           "Hugging Face, where models download from, is limiting downloads from your network. Wait a few minutes, then tap Try Again. What's downloaded so far is kept.")
        }
        if has("401 unauthorized", "403 forbidden", "(401", "(403") {
            return problem(.accessDenied, "This Model Needs Approval",
                           "\(model)'s owner requires you to accept their license on huggingface.co before downloading, which Sapient can't do for you. Pick another model in Models.")
        }
        if has("404 not found", "(404") {
            return problem(.notFound, "Model Files Not Found",
                           "Hugging Face no longer has the files for \(model). Pick another model in Models; an app update may bring a fixed catalog.")
        }
        if let status = serverErrorStatus(lower) {
            return problem(.hubError, "Hugging Face Is Having Trouble",
                           "The download server answered with an error (\(status)). This is usually brief: wait a minute, then tap Try Again. What's downloaded so far is kept.")
        }
        if has("peer closed", "connection reset", "os error 54", "broken pipe", "os error 32", "error decoding response body",
               "unexpected eof", "body from connection", "connection closed") {
            return problem(.interrupted, "Download Interrupted",
                           "The connection dropped while downloading \(model)\(soFar). Tap Resume to continue from where it stopped.")
        }
        if has("connection refused", "os error 61", "timed out", "os error 60", "tls", "certificate", "tcp connect error") {
            return problem(.hubUnreachable, "Can't Reach Hugging Face",
                           "\(model) downloads from huggingface.co, which didn't answer. If you're on school, work or public Wi-Fi, it may block that site: switch networks or use mobile data, then tap Try Again.")
        }
        if isDownload {
            return problem(.downloadFailed, "Download Failed",
                           "Something went wrong downloading \(model)\(soFar). Tap Try Again; what's downloaded so far is kept. If it keeps failing, delete \(model) in Models and download it again.")
        }
        return problem(.loadFailed, "Couldn't Load \(model)",
                       "The model's files may be damaged or incomplete. Tap Try Again; if it fails again, delete \(model) in Models and download it again.")
    }

    /// The model was loading when iOS closed the app (it ran out of memory).
    static func closedWhileLoading(model: String) -> AppProblem {
        AppProblem(
            kind: .closedWhileLoading, title: "Sapient Closed While Loading",
            message: "Sapient closed while loading \(model), most likely because the phone ran out of memory. Tap Try Again: idle models are released first to make room, and if it still can't fit you'll be told instead."
        )
    }

    /// "(503 Service Unavailable)" → "503"; nil unless it's a 5xx.
    private static func serverErrorStatus(_ lower: String) -> String? {
        guard lower.contains("server error") || lower.contains("service unavailable") || lower.contains("bad gateway") else { return nil }
        return lower.firstMatch(of: /\((5\d\d)[ )]/).map { String($0.1) } ?? "5xx"
    }
}

nonisolated extension AppProblem: LocalizedError {
    var errorDescription: String? { summary }
}
