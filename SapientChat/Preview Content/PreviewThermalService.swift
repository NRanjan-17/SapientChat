/// `ThermalService` for SwiftUI previews: always reports a fixed state.
nonisolated struct PreviewThermalService: ThermalService {
    var pressure: ThermalPressure = .nominal

    func pressureUpdates() -> AsyncStream<ThermalPressure> {
        AsyncStream { continuation in
            continuation.yield(pressure)
        }
    }
}
