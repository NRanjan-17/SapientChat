// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Sapient

/// The linked SAPIENT engine's version, e.g. "0.6.6".
nonisolated enum SapientVersion {
    static var current: String { version() }
}
