// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// What has to happen before a model can be used.
nonisolated enum LoadPlan: Equatable, Sendable {
    case alreadyLoaded
    /// Release these models (least recently used first), then load.
    case load(releasing: [String])
    /// Won't fit even with every idle model released.
    case wontFit(String)
    /// Would fit, but only by releasing models answering right now; it can
    /// load once they finish.
    case busy(String)

    /// Whether it can load now or once busy models finish.
    var fits: Bool {
        if case .wontFit = self { false } else { true }
    }
}

/// Decides which loaded models to release so a new one fits, keeping up to
/// `capacity` models together when memory allows. Only idle models are
/// released, least recently used first: a model answering a chat or an API
/// request is never pulled out from under it.
nonisolated enum MemoryPlanner {
    /// - Parameters:
    ///   - loaded: models in memory, most recently used first (nil = not in
    ///     the catalog, so its size is unknown).
    ///   - availableBytes: what iOS still lets the app allocate; nil = no
    ///     known limit (simulator), so only capacity matters.
    ///   - busy: loaded models generating right now.
    ///   - size: memory a model takes once loaded; the estimate by default,
    ///     or what a model really took when that was more.
    static func plan(
        loading model: PhoneModel,
        loaded: [(alias: String, model: PhoneModel?)],
        availableBytes: UInt64?,
        capacity: Int = LoadedSlots<Void>.defaultCapacity,
        busy: Set<String> = [],
        size: (PhoneModel) -> UInt64 = \.estimatedMemoryBytes
    ) -> LoadPlan {
        if loaded.contains(where: { $0.alias == model.alias }) {
            return .alreadyLoaded
        }
        // Idle models, least recently used first: the ones to release.
        var idle = loaded.reversed().filter { !busy.contains($0.alias) }
        var kept = loaded.count
        var releasing: [String] = []
        var freed: UInt64 = 0

        func releaseNext() {
            let released = idle.removeFirst()
            releasing.append(released.alias)
            kept -= 1
            let bytes = released.model.map(size) ?? 0
            freed = freed > UInt64.max - bytes ? .max : freed + bytes
        }

        while kept >= capacity, !idle.isEmpty {
            releaseNext()
        }
        let need = size(model)
        if kept >= capacity {
            return .busy(busyMessage(model, busy: busy, need: need, have: availableBytes))
        }
        // No known limit (simulator): capacity is the only constraint.
        guard let availableBytes else { return .load(releasing: releasing) }

        while model.fitProblem(availableBytes: availableBytes, reclaimableBytes: freed, requiredBytes: need) != nil,
              !idle.isEmpty {
            releaseNext()
        }
        guard let problem = model.fitProblem(availableBytes: availableBytes, reclaimableBytes: freed, requiredBytes: need) else {
            return .load(releasing: releasing)
        }
        // Would releasing the busy ones too make room? Then it's only a wait.
        let busyBytes = loaded.filter { busy.contains($0.alias) }.reduce(UInt64(0)) { $0 + ($1.model.map(size) ?? 0) }
        if busyBytes > 0, model.fitProblem(availableBytes: availableBytes, reclaimableBytes: freed + busyBytes, requiredBytes: need) == nil {
            return .busy(busyMessage(model, busy: busy, need: need, have: availableBytes + freed))
        }
        return .wontFit(problem)
    }

    private static func busyMessage(_ model: PhoneModel, busy: Set<String>, need: UInt64, have: UInt64?) -> String {
        let names = busy.sorted().map { $0.split(separator: "/").last.map(String.init) ?? $0 }.formatted(.list(type: .and))
        let room = have.map { ", and iOS allows about \(Format.bytes($0)) once idle models are released" } ?? ""
        return "\(model.displayName) needs about \(Format.bytes(need))\(room). \(names) is answering right now, so it can't be released yet. Wait for that reply to finish, then tap Try Again."
    }
}
