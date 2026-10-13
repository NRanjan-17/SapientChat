// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// How a model picks each next token, beyond temperature. Nil fields use
/// the engine's defaults.
nonisolated struct SamplingSettings: Equatable, Sendable, Codable {
    /// Nucleus sampling: only the most likely tokens adding up to this
    /// probability are considered. Used with a temperature above Precise.
    var topP: Double?
    /// Only the K most likely tokens are considered. Used with a
    /// temperature above Precise.
    var topK: Int?
    /// Above 1 makes repeating recent tokens less likely.
    var repetitionPenalty: Double?

    static let topPRange: ClosedRange<Double> = 0.05...1
    static let topKRange = 1...200
    static let repetitionPenaltyRange: ClosedRange<Double> = 1...2

    var isDefault: Bool { self == SamplingSettings() }

    /// Out-of-range values clamped; a repetition penalty of 1 is none.
    var normalized: SamplingSettings {
        var copy = self
        copy.topP = topP.map { min(max($0, Self.topPRange.lowerBound), Self.topPRange.upperBound) }
        copy.topK = topK.map { min(max($0, Self.topKRange.lowerBound), Self.topKRange.upperBound) }
        copy.repetitionPenalty = repetitionPenalty
            .map { min(max($0, Self.repetitionPenaltyRange.lowerBound), Self.repetitionPenaltyRange.upperBound) }
            .flatMap { $0 > 1 ? $0 : nil }
        return copy
    }
}

/// The sampling settings picked per model. SAPIENT applies them when a
/// model loads, so changing them reloads a model that's in memory. There is
/// no seed: the engine doesn't take one (Precise is already repeatable).
nonisolated final class SamplingStore: @unchecked Sendable {
    static let standard = SamplingStore(defaults: .standard)

    // UserDefaults is thread-safe.
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func settings(for alias: String) -> SamplingSettings {
        guard let data = defaults.data(forKey: key(alias)),
              let settings = try? JSONDecoder().decode(SamplingSettings.self, from: data)
        else { return SamplingSettings() }
        return settings.normalized
    }

    func set(_ settings: SamplingSettings, for alias: String) {
        let settings = settings.normalized
        if settings.isDefault {
            defaults.removeObject(forKey: key(alias))
        } else if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key(alias))
        }
    }

    private func key(_ alias: String) -> String {
        "sampling." + alias
    }
}
