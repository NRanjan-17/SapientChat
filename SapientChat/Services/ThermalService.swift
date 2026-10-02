/// Reports the device's thermal state.
nonisolated protocol ThermalService: Sendable {
    /// Yields the current state immediately, then every change, until the
    /// consuming task is cancelled.
    func pressureUpdates() -> AsyncStream<ThermalPressure>
}
