// swift-tools-version:5.9
// SPDX-License-Identifier: AGPL-3.0-only
// Copyright (C) 2026 OpenHorizon Labs Pvt Ltd — Sapient Studio: AGPL-3.0-only OR commercial (see LICENSE, NOTICE)

import PackageDescription

// Sapient Island: a small native Mac app that shows what Sapient Studio is
// doing at the MacBook's camera notch, like the Dynamic Island on iPhone.
// Build and run: `swift run -c release` in this folder.
let package = Package(
    name: "SapientIsland",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "SapientIsland", path: "Sources/SapientIsland")
    ]
)
