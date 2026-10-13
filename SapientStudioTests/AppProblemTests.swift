// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Testing
@testable import SapientStudio

/// The engine's real error text for each download failure, recorded from
/// SAPIENT v0.6.7 (`downloadModel`, then `String(describing:)`, which is what
/// the app showed before), and what the app shows now.
struct AppProblemTests {
    static let recorded: [(name: String, text: String, kind: AppProblem.Kind)] = [
        ("offline", #"Load(reason: "Failed to download model 'openhorizon/smollm2-135m-q4': Failed to fetch model file listing from HuggingFace Hub: request error: error sending request for url (https://huggingface.co/api/models/unsloth/SmolLM2-135M-Instruct-GGUF/revision/main): error sending request for url (https://huggingface.co/api/models/unsloth/SmolLM2-135M-Instruct-GGUF/revision/main): client error (Connect): dns error: failed to lookup address information: nodename nor servname provided, or not known")"#, .noNetwork),
        ("hub refused", #"Load(reason: "Failed to download model 'openhorizon/smollm2-135m-q4': Failed to fetch model file listing from HuggingFace Hub: request error: error sending request for url (http://127.0.0.1:9/api/models/unsloth/SmolLM2-135M-Instruct-GGUF/revision/main): error sending request for url (http://127.0.0.1:9/api/models/unsloth/SmolLM2-135M-Instruct-GGUF/revision/main): client error (Connect): tcp connect error: Connection refused (os error 61)")"#, .hubUnreachable),
        ("hub 503", #"Load(reason: "Failed to download model 'openhorizon/smollm2-135m-q4': Failed to fetch model file listing from HuggingFace Hub: request error: HTTP status server error (503 Service Unavailable) for url (http://127.0.0.1:18503/api/models/unsloth/SmolLM2-135M-Instruct-GGUF/revision/main): HTTP status server error (503 Service Unavailable) for url (http://127.0.0.1:18503/api/models/unsloth/SmolLM2-135M-Instruct-GGUF/revision/main)")"#, .hubError),
        ("gated", #"Load(reason: "Failed to download model 'openhorizon/llama-3.2-3b': Failed to download 'model-00001-of-00002.safetensors': request error: HTTP status client error (401 Unauthorized) for url (https://huggingface.co/meta-llama/Llama-3.2-3B-Instruct/resolve/main/model-00001-of-00002.safetensors)")"#, .accessDenied),
        ("disk full", #"Load(reason: "Failed to download model 'openhorizon/smollm2-135m-q4': Failed to download GGUF weights 'SmolLM2-135M-Instruct-Q4_K_M.gguf': I/O error No space left on device (os error 28): No space left on device (os error 28)")"#, .storageFull),
        ("connection dropped", #"Load(reason: "Failed to download model 'openhorizon/smollm2-135m-q4': Failed to download GGUF weights 'SmolLM2-135M-Instruct-Q4_K_M.gguf': request error: error decoding response body: error decoding response body: error reading a body from connection: peer closed connection without sending TLS close_notify: https://docs.rs/rustls/latest/rustls/manual/_03_howto/index.html#unexpected-eof")"#, .interrupted),
        ("rate limit", #"Load(reason: "Failed to download model 'openhorizon/smollm2-135m-q4': Failed to fetch model file listing from HuggingFace Hub: request error: HTTP status client error (429 Too Many Requests) for url (http://127.0.0.1:18429/api/models/unsloth/SmolLM2-135M-Instruct-GGUF/revision/main): HTTP status client error (429 Too Many Requests) for url (http://127.0.0.1:18429/api/models/unsloth/SmolLM2-135M-Instruct-GGUF/revision/main)")"#, .rateLimited),
    ]

    @Test(arguments: recorded.indices)
    func sortsEachRecordedFailure(_ index: Int) {
        let (name, text, kind) = Self.recorded[index]
        let problem = AppProblem.classify(text, model: "smollm2-135m-q4")
        #expect(problem.kind == kind, "\(name)")
        #expect(problem.details == text, "the engine text stays available to copy")
        #expect(!problem.message.contains("Load(reason"), "no developer text in the message")
    }

    /// Every message says what to do next, not just what failed.
    @Test(arguments: recorded.indices)
    func everyMessageSaysWhatToDoNext(_ index: Int) {
        let problem = AppProblem.classify(Self.recorded[index].text, model: "m")
        let actions = ["tap try again", "tap resume", "pick another model", "wait"]
        #expect(actions.contains { problem.message.lowercased().contains($0) }, "\(problem.message)")
    }

    @Test func offlineWinsWhenTheDeviceHasNoNetwork() {
        let problem = AppProblem.classify("tcp connect error: Connection refused", model: "m", isOffline: true)
        #expect(problem.kind == .noNetwork)
    }

    @Test func interruptedAndStorageFullOfferResumeWithProgress() {
        let progress = DownloadProgress(downloadedBytes: 400_000_000, totalBytes: 1_000_000_000)
        let dropped = AppProblem.classify("peer closed connection", model: "m", progress: progress)
        #expect(dropped.retryTitle == "Resume")
        #expect(dropped.message.contains(progress.text))
        let full = AppProblem.classify("No space left on device (os error 28)", model: "m", progress: progress, device: "iPad")
        #expect(full.retryTitle == "Resume")
        #expect(full.message.contains("iPad Storage"))
    }

    @Test func gatedAndMissingModelsDontOfferTryAgain() {
        #expect(!AppProblem.classify("(401 Unauthorized)", model: "m").canRetry)
        #expect(!AppProblem.classify("(404 Not Found)", model: "m").canRetry)
        #expect(AppProblem.classify("(503 Service Unavailable) server error", model: "m").canRetry)
    }

    @Test func memoryErrorsKeepTheirAdvice() {
        let fit = AppProblem.from(ChatViewModelError.wontFit("Pick a smaller model."), model: "m")
        #expect(fit.kind == .notEnoughMemory && fit.message == "Pick a smaller model.")
        let busy = AppProblem.from(ChatViewModelError.busy("Wait for that reply to finish."), model: "m")
        #expect(busy.kind == .memoryBusy && busy.canRetry)
    }

    @Test func apiCodesAndStatuses() {
        let offline = AppProblem.classify("dns error", model: "m")
        #expect(offline.code == "no_network")
        #expect(offline.httpStatus == 502)
        #expect(AppProblem.classify("429 Too Many Requests", model: "m").httpStatus == 429)
        #expect(AppProblem.classify("os error 28", model: "m").httpStatus == 507)
    }
}

struct MemoryPlannerIdleFirstTests {
    let small = TestModels.small
    let big = TestModels.big
    let medium = PhoneModel(alias: "org/medium", repoId: "org/medium", params: "360M", billions: 0.36)

    @Test func releasesIdleModelsButNeverOneThatsAnswering() {
        // Most recently used first: medium, then small (least recent).
        let loaded: [(alias: String, model: PhoneModel?)] = [(medium.alias, medium), (small.alias, small)]
        let need = big.estimatedMemoryBytes
        let available = need - small.estimatedMemoryBytes - medium.estimatedMemoryBytes + 1
        let plan = MemoryPlanner.plan(loading: big, loaded: loaded, availableBytes: available + medium.estimatedMemoryBytes, busy: [small.alias])
        #expect(plan == .load(releasing: [medium.alias]), "small is answering, so the idle medium goes")
    }

    @Test func saysWaitWhenOnlyABusyModelIsInTheWay() {
        let loaded: [(alias: String, model: PhoneModel?)] = [(small.alias, small)]
        let available = big.estimatedMemoryBytes - small.estimatedMemoryBytes / 2
        let plan = MemoryPlanner.plan(loading: big, loaded: loaded, availableBytes: available, busy: [small.alias])
        guard case .busy(let message) = plan else { Issue.record("expected busy, got \(plan)"); return }
        #expect(message.contains("Wait for that reply to finish"))
        #expect(plan.fits, "it will fit once the reply ends")
    }

    @Test func plansWithAMeasuredSizeWhenItsBigger() {
        let available = small.estimatedMemoryBytes + 1
        #expect(MemoryPlanner.plan(loading: small, loaded: [], availableBytes: available) == .load(releasing: []))
        let measured = MemoryPlanner.plan(loading: small, loaded: [], availableBytes: available, size: { _ in available * 2 })
        guard case .wontFit = measured else { Issue.record("expected wontFit, got \(measured)"); return }
    }
}

struct ModelMemoryLedgerTests {
    @Test func remembersTheLatestMeasuredSize() {
        let ledger = makeMemoryLedger()
        ledger.beginLoad("a", availableBytes: 3_000)
        ledger.finishLoad("a", grewBy: 1_000)
        ledger.beginLoad("a", availableBytes: 3_000)
        ledger.finishLoad("a", grewBy: 800)
        #expect(ledger.requiredBytes(for: "a") == 800, "the latest measurement wins")
        #expect(ledger.takeLoadThatEndedTheApp() == nil, "both loads were crossed off")
    }

    @Test func aLoadNeverCrossedOffIsReportedButDoesntResizeTheModel() {
        let defaults = UserDefaults(suiteName: "ledger-\(UUID().uuidString)")!
        ModelMemoryLedger(defaults: defaults).beginLoad("small", availableBytes: 5_000_000_000)
        // Next launch: a new ledger over the same storage.
        let relaunched = ModelMemoryLedger(defaults: defaults)
        #expect(relaunched.takeLoadThatEndedTheApp() == "small")
        #expect(relaunched.requiredBytes(for: "small") == nil,
                "being loaded when the app ended doesn't mean it needed 5 GB (that's how a 135M model pushed out a 1.7B)")
        #expect(relaunched.takeLoadThatEndedTheApp() == nil, "reported once")
    }

    @Test func aLoadThatThrewTeachesNothing() {
        let ledger = makeMemoryLedger()
        ledger.beginLoad("a", availableBytes: 2_000)
        ledger.abandonLoad()
        #expect(ledger.takeLoadThatEndedTheApp() == nil)
        #expect(ledger.requiredBytes(for: "a") == nil)
    }
}
