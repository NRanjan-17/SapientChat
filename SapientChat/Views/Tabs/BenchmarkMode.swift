// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// The Benchmark tab's two modes.
nonisolated enum BenchmarkMode: String, CaseIterable, Sendable {
    case single
    case compare

    var title: String {
        switch self {
        case .single: "Single Model"
        case .compare: "Compare"
        }
    }
}
