/// The device's thermal state, as shown to the user.
nonisolated enum ThermalPressure: Equatable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    /// Nil when there is nothing worth showing.
    var label: String? {
        switch self {
        case .nominal: nil
        case .fair: "thermal: fair"
        case .serious: "thermal: serious"
        case .critical: "thermal: critical"
        }
    }
}
