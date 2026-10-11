// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// What each model really takes in memory, learned as models load, so the
/// memory plan stops trusting an estimate that turned out low.
///
/// A load that runs out of memory doesn't throw: iOS ends the app. So each
/// load is written down before it starts and crossed off after; one still
/// written down at launch is a load iOS ended the app during. That model is
/// then known to need more than was free at the time, and the app says so
/// instead of trying the same thing again.
nonisolated final class ModelMemoryLedger: @unchecked Sendable {
    static let standard = ModelMemoryLedger(defaults: .standard)

    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// Bytes `alias` is known to need, if it was measured (or ended the app).
    func requiredBytes(for alias: String) -> UInt64? {
        lock.withLock { sizes[alias] }
    }

    /// Writes down the load about to start, with the memory free before it.
    func beginLoad(_ alias: String, availableBytes: UInt64?) {
        lock.withLock {
            defaults.set(["model": alias, "available": availableBytes.map { NSNumber(value: $0) } ?? NSNumber(value: 0)],
                         forKey: Keys.inFlight)
        }
    }

    /// Crosses the load off and remembers how much the footprint grew.
    func finishLoad(_ alias: String, grewBy bytes: UInt64?) {
        lock.withLock {
            defaults.removeObject(forKey: Keys.inFlight)
            guard let bytes, bytes > 0 else { return }
            var all = sizes
            all[alias] = max(all[alias] ?? 0, bytes)
            sizes = all
        }
    }

    /// A load that didn't get crossed off without the app being ended (it
    /// threw): nothing learned.
    func abandonLoad() {
        lock.withLock { defaults.removeObject(forKey: Keys.inFlight) }
    }

    /// The model iOS ended the app while loading, once, at launch. It's
    /// recorded as needing more than was free when it tried.
    func takeLoadThatEndedTheApp() -> String? {
        lock.withLock {
            guard let entry = defaults.dictionary(forKey: Keys.inFlight), let alias = entry["model"] as? String else { return nil }
            defaults.removeObject(forKey: Keys.inFlight)
            if let free = (entry["available"] as? NSNumber)?.uint64Value, free > 0 {
                var all = sizes
                all[alias] = max(all[alias] ?? 0, free + 1)
                sizes = all
            }
            return alias
        }
    }

    // MARK: Storage

    private enum Keys {
        static let sizes = "memory.measuredBytes"
        static let inFlight = "memory.loadInFlight"
    }

    private var sizes: [String: UInt64] {
        get {
            (defaults.dictionary(forKey: Keys.sizes) as? [String: NSNumber])?.mapValues(\.uint64Value) ?? [:]
        }
        set {
            defaults.set(newValue.mapValues { NSNumber(value: $0) }, forKey: Keys.sizes)
        }
    }
}
