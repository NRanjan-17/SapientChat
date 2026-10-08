// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation
import SwiftData

/// A saved `RequestLogEntry`. The entry is stored as JSON, so its fields can
/// grow without a schema migration; date is kept apart for sorting.
@Model
final class RequestRecord {
    var id: UUID
    var date: Date
    var payload: Data

    init(_ entry: RequestLogEntry) {
        id = entry.id
        date = entry.date
        payload = (try? JSONEncoder().encode(entry)) ?? Data()
    }

    var entry: RequestLogEntry? {
        try? JSONDecoder().decode(RequestLogEntry.self, from: payload)
    }
}
