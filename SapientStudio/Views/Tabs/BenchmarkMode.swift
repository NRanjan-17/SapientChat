// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// The Benchmark tab's modes.
nonisolated enum BenchmarkMode: String, CaseIterable, Sendable {
    case single
    case compare
    case promptSets

    var title: String {
        switch self {
        case .single: "Single Model"
        case .compare: "Compare"
        case .promptSets: "Prompt Sets"
        }
    }
}
