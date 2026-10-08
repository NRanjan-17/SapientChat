// swift-tools-version:6.0
// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nalinish Ranjan — SapientKit (see SapientKit/LICENSE)

// SapientKit as a Swift package other apps add by this repository's URL:
// File → Add Package Dependencies → https://github.com/NRanjan-17/SapientChat
// → product "SapientKit". Only SapientKit builds; the app's Xcode project is
// separate and unaffected.
import PackageDescription

let package = Package(
    name: "SapientKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SapientKit", targets: ["SapientKit"]),
    ],
    targets: [
        .target(name: "SapientKit", path: "SapientKit/Sources/SapientKit"),
        .testTarget(name: "SapientKitTests", dependencies: ["SapientKit"], path: "SapientKit/Tests/SapientKitTests"),
    ]
)
