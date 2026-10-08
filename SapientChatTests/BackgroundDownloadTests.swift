// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Synchronization
import Testing
@testable import SapientChat

/// Records what would go to iOS's task scheduler.
final class FakeBackgroundScheduler: BackgroundDownloadScheduler {
    final class Work: BackgroundDownload {
        var onExpire: (() -> Void)?
        var onRefused: (() -> Void)?
        private(set) var updates: [(UInt64, UInt64)] = []
        private(set) var result: Bool?
        func update(downloaded: UInt64, total: UInt64) { updates.append((downloaded, total)) }
        func finish(success: Bool) { if result == nil { result = success } }
    }

    var refuses = false
    private(set) var begun: [String] = []
    private(set) var works: [Work] = []
    private(set) var holds: [Bool] = []

    func begin(model: String, title: String) -> (any BackgroundDownload)? {
        begun.append(model)
        let work = Work()
        works.append(work)
        if refuses { Task { @MainActor in work.onRefused?() } }
        return work
    }

    func holdBriefly(active: Bool) { holds.append(active) }
}

/// Fails its first download (as if iOS cut it off), then succeeds.
final class FailsOnceDownloader: ModelDownloadService, Sendable {
    let storage: FakeStorage
    let calls = Mutex(0)

    init(storage: FakeStorage) {
        self.storage = storage
    }

    func download(model: String, onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let call = calls.withLock { $0 += 1; return $0 }
        onProgress(DownloadProgress(downloadedBytes: 100, totalBytes: 1_000))
        try await Task.sleep(for: .milliseconds(30))
        if call == 1 { throw URLError(.networkConnectionLost) }
        onProgress(DownloadProgress(downloadedBytes: 1_000, totalBytes: 1_000))
        let repo = FixedCatalog().chatModels().first { $0.alias == model }?.repoId ?? model
        storage.complete(repo, bytes: 1_000)
    }

    func downloadSize(model: String) async throws -> UInt64 { 1_000 }
}

@MainActor
struct BackgroundDownloadTests {
    @Test func aDownloadAsksIOSToKeepRunningAndReportsProgress() async throws {
        let scheduler = FakeBackgroundScheduler()
        let coordinator = DownloadCoordinator(downloads: FakeDownloader(storage: FakeStorage()), catalog: FixedCatalog())
        coordinator.background = scheduler
        try await coordinator.download(TestModels.small.alias) { _ in }
        #expect(scheduler.begun == [TestModels.small.alias])
        let work = try #require(scheduler.works.first)
        #expect(work.updates.last?.0 == 1_000)
        #expect(work.result == true)
    }

    @Test func leavingTheAppAsksForExtraTimeAndReturningEndsIt() {
        let scheduler = FakeBackgroundScheduler()
        let coordinator = DownloadCoordinator(downloads: FakeDownloader(storage: FakeStorage(), hangs: true), catalog: FixedCatalog())
        coordinator.background = scheduler
        let caller = Task { try await coordinator.download(TestModels.small.alias) { _ in } }
        coordinator.appMovedToBackground()
        coordinator.appBecameActive()
        #expect(scheduler.holds.suffix(1) == [false])
        caller.cancel()
        coordinator.cancel(TestModels.small.alias)
    }

    @Test func aDownloadCutOffInTheBackgroundResumesForTheSameCaller() async throws {
        let storage = FakeStorage()
        let downloader = FailsOnceDownloader(storage: storage)
        let coordinator = DownloadCoordinator(downloads: downloader, catalog: FixedCatalog())
        coordinator.background = FakeBackgroundScheduler()
        let caller = Task { try await coordinator.download(TestModels.small.alias) { _ in } }
        #expect(await eventually { coordinator.isDownloading(TestModels.small.alias) })
        coordinator.appMovedToBackground()
        // The first attempt fails while "suspended"; it waits for the app.
        #expect(await eventually { downloader.calls.withLock { $0 } == 1 && coordinator.isDownloading(TestModels.small.alias) })
        try? await Task.sleep(for: .milliseconds(60))
        coordinator.appBecameActive()
        try await caller.value // resumed and finished, not failed
        #expect(downloader.calls.withLock { $0 } == 2)
        #expect(storage.download(forRepo: TestModels.small.repoId).isDownloaded)
    }

    @Test func aFailureWhileTheAppIsOpenIsReported() async {
        let coordinator = DownloadCoordinator(
            downloads: FailsOnceDownloader(storage: FakeStorage()), catalog: FixedCatalog()
        )
        await #expect(throws: URLError.self) {
            try await coordinator.download(TestModels.small.alias) { _ in }
        }
    }

    @Test func whenIOSRefusesTheAppShowsItsOwnIsland() async throws {
        let scheduler = FakeBackgroundScheduler()
        scheduler.refuses = true
        let activities = RecordingLiveActivities()
        let coordinator = DownloadCoordinator(downloads: FakeDownloader(storage: FakeStorage(), steps: 10), catalog: FixedCatalog())
        coordinator.background = scheduler
        coordinator.liveActivities = activities
        try await coordinator.download(TestModels.small.alias) { _ in }
        #expect(activities.started.map(\.title) == ["Download"])
    }

    @Test func whenIOSAcceptsItsProgressReplacesTheAppsIsland() async throws {
        let activities = RecordingLiveActivities()
        let coordinator = DownloadCoordinator(downloads: FakeDownloader(storage: FakeStorage()), catalog: FixedCatalog())
        coordinator.background = FakeBackgroundScheduler()
        coordinator.liveActivities = activities
        try await coordinator.download(TestModels.small.alias) { _ in }
        #expect(activities.started.isEmpty)
    }
}

struct BackgroundTaskIdentifierTests {
    @Test func identifiersAreOneSegmentAfterThePrefixAndUnique() {
        let identifiers = (0..<50).map { _ in ContinuedProcessingDownloads.newIdentifier() }
        for identifier in identifiers {
            #expect(identifier.hasPrefix(ContinuedProcessingDownloads.identifierPrefix + "."))
            let suffix = identifier.dropFirst(ContinuedProcessingDownloads.identifierPrefix.count + 1)
            #expect(!suffix.isEmpty)
            #expect(suffix.allSatisfy { $0.isLetter || $0.isNumber }, "\(identifier)")
        }
        #expect(Set(identifiers).count == identifiers.count)
    }
}
