// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

/// Failures `ChatViewModel` raises itself (engine errors pass through).
nonisolated enum ChatViewModelError: Error {
    /// The model is estimated not to fit in the memory iOS allows.
    case wontFit(String)
    /// It would fit only by releasing a model that's answering right now.
    case busy(String)
}
