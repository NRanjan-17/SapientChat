// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import Observation
import SwiftData

/// One finished benchmark, with when and on what it ran.
nonisolated struct BenchmarkHistoryEntry: Identifiable, Equatable, Sendable, Codable {
    var id = UUID()
    var date: Date
    /// Hardware identifier, e.g. "iPhone16,2".
    var device: String
    /// e.g. "iOS 27.0.1".
    var system: String
    var result: BenchmarkResult

    /// The model's name without the catalog prefix.
    var modelName: String {
        result.model.split(separator: "/").last.map(String.init) ?? result.model
    }
}

/// A saved `BenchmarkHistoryEntry`, stored as JSON like `RequestRecord` so
/// its fields can grow without a schema migration.
@Model
final class BenchmarkRecord {
    var id: UUID
    var date: Date
    var payload: Data

    init(_ entry: BenchmarkHistoryEntry) {
        id = entry.id
        date = entry.date
        payload = (try? JSONEncoder().encode(entry)) ?? Data()
    }

    var entry: BenchmarkHistoryEntry? {
        try? JSONDecoder().decode(BenchmarkHistoryEntry.self, from: payload)
    }
}

/// Where benchmark results are kept between launches.
protocol BenchmarkHistoryStore: AnyObject {
    /// Newest first.
    func entries() -> [BenchmarkHistoryEntry]
    func insert(_ entry: BenchmarkHistoryEntry)
    func delete(_ id: UUID)
    func deleteAll()
}

final class SwiftDataBenchmarkHistoryStore: BenchmarkHistoryStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func entries() -> [BenchmarkHistoryEntry] {
        let descriptor = FetchDescriptor<BenchmarkRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.entry)
    }

    func insert(_ entry: BenchmarkHistoryEntry) {
        context.insert(BenchmarkRecord(entry))
        try? context.save()
    }

    func delete(_ id: UUID) {
        let descriptor = FetchDescriptor<BenchmarkRecord>(predicate: #Predicate { $0.id == id })
        for record in (try? context.fetch(descriptor)) ?? [] { context.delete(record) }
        try? context.save()
    }

    func deleteAll() {
        try? context.delete(model: BenchmarkRecord.self)
        try? context.save()
    }
}

/// Kept in memory only: previews and tests.
final class InMemoryBenchmarkHistoryStore: BenchmarkHistoryStore {
    private var stored: [BenchmarkHistoryEntry] = []

    func entries() -> [BenchmarkHistoryEntry] { stored.sorted { $0.date > $1.date } }
    func insert(_ entry: BenchmarkHistoryEntry) { stored.append(entry) }
    func delete(_ id: UUID) { stored.removeAll { $0.id == id } }
    func deleteAll() { stored.removeAll() }
}

/// Every benchmark run on this device, so a change in speed after an engine
/// or iOS update shows up.
@Observable
final class BenchmarkHistory {
    /// Newest first.
    private(set) var entries: [BenchmarkHistoryEntry]

    @ObservationIgnored private let store: any BenchmarkHistoryStore
    @ObservationIgnored private let device: () -> DeviceInfo

    init(store: any BenchmarkHistoryStore, device: @escaping () -> DeviceInfo = DeviceInfo.current) {
        self.store = store
        self.device = device
        entries = store.entries()
    }

    /// Saves a finished benchmark; one that was cancelled has too few runs
    /// to compare, so it's left out.
    func record(_ result: BenchmarkResult, date: Date = .now) {
        guard !result.cancelled, !result.runs.isEmpty else { return }
        let info = device()
        let entry = BenchmarkHistoryEntry(date: date, device: info.model, system: info.system, result: result)
        store.insert(entry)
        entries.insert(entry, at: 0)
    }

    func delete(_ entry: BenchmarkHistoryEntry) {
        store.delete(entry.id)
        entries.removeAll { $0.id == entry.id }
    }

    func clear() {
        store.deleteAll()
        entries.removeAll()
    }

    /// The run before `entry` that it can fairly be compared with: the same
    /// model on the same hardware and compute.
    func previous(to entry: BenchmarkHistoryEntry) -> BenchmarkHistoryEntry? {
        entries.first {
            $0.date < entry.date && $0.result.model == entry.result.model && $0.device == entry.device
                && ChatViewModel.hardware($0.result.backend) == ChatViewModel.hardware(entry.result.backend)
        }
    }

    /// Decode speed against the comparable run before it, as a fraction
    /// (0.05 is 5% faster); nil without one.
    func change(for entry: BenchmarkHistoryEntry) -> Double? {
        guard let before = previous(to: entry)?.result.meanDecodeTokensPerSecond, before > 0 else { return nil }
        return entry.result.meanDecodeTokensPerSecond / before - 1
    }

    /// Everything as a JSON array, for sharing.
    func exportJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return (try? encoder.encode(entries)).map { String(decoding: $0, as: UTF8.self) } ?? "[]"
    }
}
