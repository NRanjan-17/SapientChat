// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 Nalinish Ranjan — Sapient Chat: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import Foundation

/// Shared display formatting.
nonisolated enum Format {
    /// "2.8 GB"-style memory size.
    static func bytes(_ bytes: UInt64) -> String {
        Int64(clamping: bytes).formatted(.byteCount(style: .memory))
    }

    /// "740 MB" / "1.2 GB": whole megabytes, one decimal for gigabytes, so
    /// it fits in a chip.
    static func compactBytes(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        return value >= 1e9
            ? "\((value / 1e9).formatted(.number.precision(.fractionLength(1)))) GB"
            : "\(Int((value / 1e6).rounded())) MB"
    }

    /// "27.4"-style rate.
    static func rate(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }
}
