// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// The context window the user picked per model, for models large enough
/// that the choice matters (1.4B parameters and up). Unset means the
/// engine's default: 3072 tokens for models above ~1.5B on a phone, 8192
/// otherwise. Read by the engine when a model loads.
nonisolated final class ContextWindowStore: @unchecked Sendable {
    /// Windows offered, in tokens. 8192 is the most the engine allocates.
    static let choices = [1024, 2048, 3072, 4096, 6144, 8192]
    /// Models from this size up can pick their window.
    static let minimumBillions = 1.4

    static let standard = ContextWindowStore(defaults: .standard)

    // UserDefaults is thread-safe.
    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    static func isAdjustable(_ model: PhoneModel) -> Bool {
        model.billions >= minimumBillions
    }

    /// The picked window for `alias`, or nil for the engine's default.
    func tokens(for alias: String) -> Int? {
        let value = defaults.integer(forKey: key(alias))
        return Self.choices.contains(value) ? value : nil
    }

    /// Sets the window for `alias`; nil goes back to the default.
    func set(_ tokens: Int?, for alias: String) {
        if let tokens, Self.choices.contains(tokens) {
            defaults.set(tokens, forKey: key(alias))
        } else {
            defaults.removeObject(forKey: key(alias))
        }
    }

    private func key(_ alias: String) -> String {
        "contextWindow." + alias
    }
}
