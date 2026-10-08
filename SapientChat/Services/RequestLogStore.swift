// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import SwiftData

/// Where the request log is kept between launches.
protocol RequestLogStore: AnyObject {
    /// Newest first, at most `limit`.
    func entries(limit: Int) -> [RequestLogEntry]
    func insert(_ entry: RequestLogEntry)
    /// Drops all but the newest `count`.
    func trim(keeping count: Int)
    func deleteAll()
}

/// The app's: SwiftData, next to the chats, on this device only.
final class SwiftDataRequestLogStore: RequestLogStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func entries(limit: Int) -> [RequestLogEntry] {
        var descriptor = FetchDescriptor<RequestRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchLimit = limit
        return ((try? context.fetch(descriptor)) ?? []).compactMap(\.entry)
    }

    func insert(_ entry: RequestLogEntry) {
        context.insert(RequestRecord(entry))
        try? context.save()
    }

    func trim(keeping count: Int) {
        var descriptor = FetchDescriptor<RequestRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)])
        descriptor.fetchOffset = count
        for record in (try? context.fetch(descriptor)) ?? [] {
            context.delete(record)
        }
        try? context.save()
    }

    func deleteAll() {
        try? context.delete(model: RequestRecord.self)
        try? context.save()
    }
}

/// Kept in memory only: previews and tests.
final class InMemoryRequestLogStore: RequestLogStore {
    private(set) var stored: [RequestLogEntry] = []

    func entries(limit: Int) -> [RequestLogEntry] {
        Array(stored.sorted { $0.date > $1.date }.prefix(limit))
    }

    func insert(_ entry: RequestLogEntry) {
        stored.append(entry)
    }

    func trim(keeping count: Int) {
        stored = entries(limit: count)
    }

    func deleteAll() {
        stored.removeAll()
    }
}
