// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// What the numbers were measured on, for reports.
nonisolated struct DeviceInfo: Equatable, Sendable {
    /// Hardware identifier, e.g. "iPhone16,2" (iPhone 15 Pro Max).
    let model: String
    /// e.g. "iOS 27.0.1".
    let system: String
    let isSimulator: Bool

    /// Running on a Mac as an iPad app ("Designed for iPad").
    static var isMac: Bool { ProcessInfo.processInfo.isiOSAppOnMac }

    /// The value of a `sysctl` string, e.g. "hw.model" → "Mac15,6".
    private static func sysctl(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }

    static func current() -> DeviceInfo {
        #if targetEnvironment(simulator)
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        let isSimulator = true
        #else
        var system = utsname()
        uname(&system)
        // On a Mac `uname` says only "arm64"; its model is in sysctl.
        let machine = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let model = isMac ? sysctl("hw.model") ?? machine : machine
        let isSimulator = false
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(
            model: model,
            // An iPad app on a Mac is given the Mac's version number.
            system: "\(isMac ? "macOS" : "iOS") \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            isSimulator: isSimulator
        )
    }
}
