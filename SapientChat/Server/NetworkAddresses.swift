// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Darwin
import Foundation

/// This device's addresses that other devices can reach.
nonisolated enum NetworkAddresses {
    struct Address: Hashable, Sendable {
        /// e.g. "Wi-Fi", "Hotspot", "Ethernet".
        let label: String
        let ip: String
    }

    /// IPv4 addresses on Wi-Fi (`en0`), personal hotspot (`bridge100`) and
    /// wired/USB interfaces (`en1`+). Cellular is skipped: it isn't reachable.
    static func current() -> [Address] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return [] }
        defer { freeifaddrs(first) }

        var addresses: [Address] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            let flags = Int32(interface.ifa_flags)
            guard let address = interface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0
            else { continue }
            let name = String(cString: interface.ifa_name)
            let label: String
            if name == "en0" {
                label = "Wi-Fi"
            } else if name.hasPrefix("bridge") {
                label = "Hotspot"
            } else if name.hasPrefix("en") {
                label = "Ethernet"
            } else {
                continue
            }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            addresses.append(Address(label: label, ip: ip))
        }
        return addresses
    }
}
