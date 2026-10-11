// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// The sampling temperature picked per model. Unset (or 0) means greedy
/// decoding: the same prompt always gets the same answer, which suits small
/// models best. Higher values vary the wording more. SAPIENT applies it when
/// a model loads, so changing it reloads a model that's in memory.
nonisolated final class TemperatureStore: @unchecked Sendable {
    /// What the slider offers.
    static let range: ClosedRange<Double> = 0...1.5
    static let step = 0.1
    /// Named settings: precise (greedy), balanced, creative.
    static let presets: [(name: String, value: Double?)] = [("Precise", nil), ("Balanced", 0.7), ("Creative", 1.0)]
    /// Nucleus sampling used with any temperature above 0, as `sapient serve` does.
    static let topP: Float = 0.95

    static let standard = TemperatureStore(defaults: .standard)

    // UserDefaults is thread-safe.
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// The temperature for `alias`, or nil for greedy decoding.
    func temperature(for alias: String) -> Double? {
        guard defaults.object(forKey: key(alias)) != nil else { return nil }
        return Self.normalized(defaults.double(forKey: key(alias)))
    }

    /// Sets the temperature for `alias`; nil or 0 goes back to greedy.
    func set(_ temperature: Double?, for alias: String) {
        if let value = temperature.flatMap(Self.normalized) {
            defaults.set(value, forKey: key(alias))
        } else {
            defaults.removeObject(forKey: key(alias))
        }
    }

    /// Clamped to the range and rounded to the step; nil for 0 (greedy).
    static func normalized(_ value: Double) -> Double? {
        let clamped = min(max(value, range.lowerBound), range.upperBound)
        let rounded = (clamped / step).rounded() * step
        return rounded > 0 ? (rounded * 10).rounded() / 10 : nil
    }

    /// "0.7", or "Precise" for greedy.
    static func label(_ temperature: Double?) -> String {
        temperature.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "Precise"
    }

    private func key(_ alias: String) -> String {
        "temperature." + alias
    }
}
