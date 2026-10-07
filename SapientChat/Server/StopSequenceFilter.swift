import Foundation

/// Applies `stop` sequences to streamed text, as `sapient serve` does:
/// output ends just before the first stop sequence, which is never sent.
/// Text that might be the start of a stop sequence is held back until the
/// next fragment settles it.
nonisolated struct StopSequenceFilter {
    let stops: [String]
    private var pending = ""
    private(set) var isStopped = false

    init(_ stops: [String]) {
        self.stops = stops.filter { !$0.isEmpty }
    }

    /// Adds a fragment; returns the text that is now safe to send.
    mutating func feed(_ fragment: String) -> String {
        guard !isStopped else { return "" }
        guard !stops.isEmpty else { return fragment }
        pending += fragment
        let earliest = stops.compactMap { pending.range(of: $0) }.min { $0.lowerBound < $1.lowerBound }
        if let earliest {
            isStopped = true
            defer { pending = "" }
            return String(pending[..<earliest.lowerBound])
        }
        let held = stops.map { stop in
            (1..<stop.count).reversed().first { pending.hasSuffix(stop.prefix($0)) } ?? 0
        }.max() ?? 0
        let ready = String(pending.dropLast(held))
        pending = String(pending.suffix(held))
        return ready
    }

    /// The text still held back once generation ends.
    mutating func flush() -> String {
        defer { pending = "" }
        return isStopped ? "" : pending
    }
}
