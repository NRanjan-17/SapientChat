// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// The app's top-level sections.
nonisolated enum AppTab: String, CaseIterable, Sendable {
    case chats
    case models
    case benchmark
    case settings

    var title: String {
        switch self {
        case .chats: "Chats"
        case .models: "Models"
        case .benchmark: "Benchmark"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .chats: "bubble.left.and.bubble.right"
        case .models: "square.stack.3d.up"
        case .benchmark: "gauge.with.dots.needle.67percent"
        case .settings: "gearshape"
        }
    }
}
