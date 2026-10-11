// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Network
import Synchronization

/// Whether the device has a network path right now, so a failed download
/// can say "You're offline" for certain instead of guessing from the error.
nonisolated final class NetworkMonitor: Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let offline = Atomic<Bool>(false)

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.offline.store(path.status != .satisfied, ordering: .relaxed)
        }
        monitor.start(queue: DispatchQueue(label: "SapientChat.NetworkMonitor"))
    }

    var isOffline: Bool { offline.load(ordering: .relaxed) }
}
