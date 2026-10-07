import Sapient

/// The linked SAPIENT engine's version, e.g. "0.6.6".
nonisolated enum SapientVersion {
    static var current: String { version() }
}
