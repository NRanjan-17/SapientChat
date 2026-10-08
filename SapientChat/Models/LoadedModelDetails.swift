// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// What the engine reports about a loaded model.
nonisolated struct LoadedModelDetails: Equatable, Sendable {
    let backend: String
    /// Conversation window allocated, in tokens.
    let contextLength: Int
    let loadTimeMs: UInt64
}
