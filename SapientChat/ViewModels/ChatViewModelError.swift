// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Failures `ChatViewModel` raises itself (engine errors pass through).
nonisolated enum ChatViewModelError: Error {
    /// The model is estimated not to fit in the memory iOS allows.
    case wontFit(String)
}
