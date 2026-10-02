import Foundation

/// What the numbers were measured on, for reports.
nonisolated struct DeviceInfo: Equatable, Sendable {
    /// Hardware identifier, e.g. "iPhone16,2" (iPhone 15 Pro Max).
    let model: String
    /// e.g. "iOS 27.0.1".
    let system: String
    let isSimulator: Bool

    static func current() -> DeviceInfo {
        #if targetEnvironment(simulator)
        let model = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
        let isSimulator = true
        #else
        var system = utsname()
        uname(&system)
        let model = withUnsafeBytes(of: &system.machine) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        let isSimulator = false
        #endif
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceInfo(
            model: model,
            system: "iOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            isSimulator: isSimulator
        )
    }
}
