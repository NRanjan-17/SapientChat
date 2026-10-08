// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Testing
@testable import SapientChat

/// Records what would go to ActivityKit.
final class RecordingLiveActivities: LiveActivityService {
    private(set) var started: [SapientActivityAttributes] = []
    private(set) var startStates: [SapientActivityAttributes.ContentState] = []
    private(set) var updates: [SapientActivityAttributes.ContentState] = []
    private(set) var ended: [SapientActivityAttributes.ContentState] = []

    func start(_ attributes: SapientActivityAttributes, state: SapientActivityAttributes.ContentState) -> UUID? {
        started.append(attributes)
        startStates.append(state)
        return UUID()
    }

    func update(_ id: UUID, state: SapientActivityAttributes.ContentState) {
        updates.append(state)
    }

    func end(_ id: UUID, state: SapientActivityAttributes.ContentState) {
        ended.append(state)
    }
}

/// A clock the test moves by hand.
final class ManualClock {
    var now = Date(timeIntervalSince1970: 1_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

@MainActor
struct LiveActivityTrackerTests {
    @Test func tracksPhasesTokensAndFinalStats() {
        let service = RecordingLiveActivities()
        let clock = ManualClock()
        let tracker = LiveActivityTracker(service: service, title: "API request", clock: { clock.now })
        tracker.start(model: "SmolLM2 135M")
        tracker.phase(.loading)
        tracker.generating()
        clock.advance(0.2)
        tracker.token()
        clock.advance(0.5)
        tracker.token()
        tracker.token()
        tracker.finish()

        #expect(service.started.map(\.model) == ["SmolLM2 135M"])
        #expect(service.updates.map(\.phase) == [.loading, .generating, .generating])
        let final = try! #require(service.ended.first)
        #expect(final.phase == .finished)
        #expect(final.tokens == 3)
        #expect(final.timeToFirstTokenMs == 200)
        #expect(final.tokensPerSecond == 4) // 2 more tokens in 0.5 s
        #expect(final.endedAt == clock.now)
    }

    @Test func throttlesTokenUpdatesToAboutOncePerSecond() {
        let service = RecordingLiveActivities()
        let clock = ManualClock()
        let tracker = LiveActivityTracker(service: service, title: "API request", clock: { clock.now })
        tracker.start(model: "m")
        tracker.generating()
        for _ in 0..<20 {
            clock.advance(0.1)
            tracker.token()
        }
        // 2 s of tokens: generating, the first token, then one more about a
        // second later. Without throttling this would be 21 updates.
        #expect(service.updates.count == 3)
    }

    @Test func failingEndsOnceWithTheMessage() {
        let service = RecordingLiveActivities()
        let tracker = LiveActivityTracker(service: service, title: "Benchmark")
        tracker.start(model: "m")
        tracker.fail("Not enough memory")
        tracker.finish()
        #expect(service.ended.map(\.phase) == [.failed])
        #expect(service.ended.first?.detail == "Not enough memory")
    }

    @Test func benchmarkProgressShowsTheRunAndItsSpeed() {
        let service = RecordingLiveActivities()
        let tracker = LiveActivityTracker(service: service, title: "Benchmark")
        tracker.start(model: "m")
        let run = BenchmarkRunResult(
            index: 1, isWarmup: false, ttftMs: 120, elapsedMs: 900, tokens: 64,
            decodeTokensPerSecond: 31.5, prefillTokensPerSecond: 200, hitEndOfTurn: false, footprintBytes: nil
        )
        tracker.benchmark(completed: 1, total: 3, lastRun: run)
        let state = try! #require(service.updates.last)
        #expect(state.phase == .benchmarking)
        #expect(state.detail == "Run 2 of 3")
        #expect(state.tokensPerSecond == 31.5)
        #expect(state.timeToFirstTokenMs == 120)
    }

    @Test func nothingIsSentWhenTheActivityCouldNotStart() {
        let tracker = LiveActivityTracker(service: NoLiveActivities(), title: "API request")
        tracker.start(model: "m")
        tracker.generating()
        tracker.token()
        tracker.finish()
        #expect(tracker.state.phase == .finished)
    }
}

@MainActor
struct ServeRouterLiveActivityTests {
    private func makeRouter() -> (ServeRouter, RecordingLiveActivities) {
        let services = makeServices(chat: ControlledChatService(autoReply: ["Hel", "lo", "!"]), storage: downloadedStorage())
        let device = DeviceStatus(memoryService: FixedMemory(), thermalService: SilentThermalService())
        let router = ServeRouter(services: services, device: device)
        let activities = RecordingLiveActivities()
        router.liveActivities = activities
        return (router, activities)
    }

    @Test func aChatRequestShowsTheModelAndItsTokens() async throws {
        let (router, activities) = makeRouter()
        let request = HTTPRequest(method: "POST", path: "/v1/chat/completions", body: Data("""
            {"model":"\(TestModels.small.alias)","messages":[{"role":"user","content":"Hi"}]}
            """.utf8))
        let response = await router.handle(request, source: "Shortcuts")
        #expect(response.status == 200)
        #expect(activities.started.first?.title == "Request from Shortcuts")
        #expect(activities.started.first?.model == TestModels.small.displayName)
        #expect(activities.ended.first?.phase == .finished)
        #expect(activities.ended.first?.tokens == 3)
    }

    @Test func readOnlyRequestsShowNothing() async {
        let (router, activities) = makeRouter()
        _ = await router.handle(HTTPRequest(method: "GET", path: "/v1/health"))
        _ = await router.handle(HTTPRequest(method: "GET", path: "/v1/catalog"))
        #expect(activities.started.isEmpty)
    }

    @Test func anUnknownModelFailsBeforeStarting() async {
        let (router, activities) = makeRouter()
        let request = HTTPRequest(method: "POST", path: "/v1/chat/completions", body: Data("""
            {"model":"nope","messages":[{"role":"user","content":"Hi"}]}
            """.utf8))
        #expect(await router.handle(request).status == 400)
        #expect(activities.started.isEmpty)
    }
}
