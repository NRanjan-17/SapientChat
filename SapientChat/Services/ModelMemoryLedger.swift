// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// What each model really takes in memory, learned as models load, so the
/// memory plan stops trusting an estimate that turned out low.
///
/// A load that runs out of memory doesn't throw: iOS ends the app. So each
/// load is written down before it starts and crossed off after; one still
/// written down at launch is a load the app was ended during, which the app
/// then says. It teaches nothing about that model's size: the phone may
/// have run out because of the models already loaded, or the app may have
/// been stopped for another reason, and blaming the model made a 135M model
/// push out everything else.
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

    /// Crosses the load off and remembers how much RAM it took. A real
    /// measurement replaces an earlier one, or a guess from a load iOS
    /// ended the app during (which may have been something else).
    func finishLoad(_ alias: String, grewBy bytes: UInt64?) {
        lock.withLock {
            defaults.removeObject(forKey: Keys.inFlight)
            guard let bytes, bytes > 0 else { return }
            var all = sizes
            all[alias] = bytes
            sizes = all
        }
    }

    /// A load that didn't get crossed off without the app being ended (it
    /// threw): nothing learned.
    func abandonLoad() {
        lock.withLock { defaults.removeObject(forKey: Keys.inFlight) }
    }

    /// The model the app was ended while loading, once, at launch.
    func takeLoadThatEndedTheApp() -> String? {
        lock.withLock {
            guard let entry = defaults.dictionary(forKey: Keys.inFlight), let alias = entry["model"] as? String else { return nil }
            defaults.removeObject(forKey: Keys.inFlight)
            return alias
        }
    }

    // MARK: Storage

    private enum Keys {
        // v2: measured as resident RAM, mapped model files included (v1
        // counted only the footprint and read low).
        static let sizes = "memory.measuredBytes.v2"
        static let inFlight = "memory.loadInFlight.v2"
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
