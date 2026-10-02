import Foundation
import Testing
@testable import SapientChat

struct LoadedSlotsTests {
    @Test func keepsTwoAndReleasesTheLeastRecentlyUsed() {
        var slots = LoadedSlots<Int>()
        #expect(slots.insert("a", session: 1).isEmpty)
        #expect(slots.insert("b", session: 2).isEmpty)
        #expect(slots.models == ["b", "a"])
        // Using "a" makes "b" the least recently used.
        #expect(slots.use("a") == 1)
        #expect(slots.insert("c", session: 3) == ["b"])
        #expect(slots.models == ["c", "a"])
    }

    @Test func reinsertingDoesNotDuplicate() {
        var slots = LoadedSlots<Int>()
        slots.insert("a", session: 1)
        slots.insert("a", session: 2)
        #expect(slots.models == ["a"])
        #expect(slots.use("a") == 2)
        #expect(slots.use("missing") == nil)
    }
}

struct MemoryPlannerTests {
    private let small = TestModels.small
    private let big = TestModels.big
    private let medium = PhoneModel(alias: "openhorizon/medium-q4", repoId: "org/medium", params: "1B Q4_K_M", billions: 1)

    @Test func alreadyLoadedNeedsNothing() {
        let plan = MemoryPlanner.plan(loading: small, loaded: [(small.alias, small)], availableBytes: 1)
        #expect(plan == .alreadyLoaded)
    }

    @Test func keepsBothWhenTheyFitTogether() {
        // small ≈0.68 GB loaded; medium ≈1.2 GB fits in 2 GB without releasing.
        let plan = MemoryPlanner.plan(loading: medium, loaded: [(small.alias, small)], availableBytes: 2_000_000_000)
        #expect(plan == .load(releasing: []))
    }

    @Test func releasesTheOtherModelWhenBothDoNotFit() {
        // medium ≈1.2 GB, only 0.7 GB free; releasing small (≈0.68 GB) makes room.
        let plan = MemoryPlanner.plan(loading: medium, loaded: [(small.alias, small)], availableBytes: 700_000_000)
        #expect(plan == .load(releasing: [small.alias]))
    }

    @Test func aFullSetReleasesTheLeastRecentlyUsed() {
        let loaded: [(alias: String, model: PhoneModel?)] = [(medium.alias, medium), (small.alias, small)]
        let plan = MemoryPlanner.plan(loading: big, loaded: loaded, availableBytes: 10_000_000_000)
        #expect(plan == .load(releasing: [small.alias]), "two slots: small was used least recently")
    }

    @Test func refusesWhenEvenReleasingEverythingIsNotEnough() {
        let plan = MemoryPlanner.plan(loading: big, loaded: [(small.alias, small)], availableBytes: 1_000_000_000)
        guard case .wontFit(let message) = plan else {
            Issue.record("expected wontFit, got \(plan)")
            return
        }
        #expect(message.contains("smollm2-1.7b"))
    }

    @Test func withNoKnownLimitOnlyCapacityMatters() {
        #expect(MemoryPlanner.plan(loading: big, loaded: [(small.alias, small)], availableBytes: nil) == .load(releasing: []))
        let full: [(alias: String, model: PhoneModel?)] = [(medium.alias, medium), (small.alias, small)]
        #expect(MemoryPlanner.plan(loading: big, loaded: full, availableBytes: nil) == .load(releasing: [small.alias]))
    }
}
