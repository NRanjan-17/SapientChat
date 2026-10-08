// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// What has to happen before a model can be used.
nonisolated enum LoadPlan: Equatable, Sendable {
    case alreadyLoaded
    /// Release these models (least recently used first), then load.
    case load(releasing: [String])
    /// Won't fit even with every other model released.
    case wontFit(String)

    var fits: Bool {
        if case .wontFit = self { false } else { true }
    }
}

/// Decides which loaded models to release so a new one fits, keeping up to
/// `capacity` models together when memory allows.
nonisolated enum MemoryPlanner {
    /// - Parameters:
    ///   - loaded: models in memory, most recently used first (nil = not in
    ///     the catalog, so its size is unknown).
    ///   - availableBytes: what iOS still lets the app allocate; nil = no
    ///     known limit (simulator), so only capacity matters.
    static func plan(
        loading model: PhoneModel,
        loaded: [(alias: String, model: PhoneModel?)],
        availableBytes: UInt64?,
        capacity: Int = LoadedSlots<Void>.defaultCapacity
    ) -> LoadPlan {
        if loaded.contains(where: { $0.alias == model.alias }) {
            return .alreadyLoaded
        }
        var keep = loaded
        var releasing: [String] = []
        var freed: UInt64 = 0

        func releaseLeastRecent() {
            let released = keep.removeLast()
            releasing.append(released.alias)
            let size = released.model?.estimatedMemoryBytes ?? 0
            freed = freed > UInt64.max - size ? .max : freed + size
        }

        while keep.count >= capacity {
            releaseLeastRecent()
        }
        // No known limit (simulator): capacity is the only constraint.
        guard let availableBytes else { return .load(releasing: releasing) }

        func fits() -> Bool {
            model.fitProblem(availableBytes: availableBytes, reclaimableBytes: freed) == nil
        }
        while !fits(), !keep.isEmpty {
            releaseLeastRecent()
        }
        if let problem = model.fitProblem(availableBytes: availableBytes, reclaimableBytes: freed) {
            return .wontFit(problem)
        }
        return .load(releasing: releasing)
    }
}
