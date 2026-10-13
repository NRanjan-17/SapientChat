// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

nonisolated enum ChatServiceError: LocalizedError, Sendable {
    case noModelLoaded
    /// The reply was cut off because it had become the same few tokens on
    /// repeat. What arrived before that is kept; this says why it ended.
    case stoppedRepeating

    var errorDescription: String? {
        switch self {
        case .noModelLoaded: "No model is loaded."
        case .stoppedRepeating: "The reply was stopped because it kept repeating itself."
        }
    }
}
