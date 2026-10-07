// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SapientKit",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SapientKit", targets: ["SapientKit"]),
    ],
    targets: [
        .target(name: "SapientKit"),
        .testTarget(name: "SapientKitTests", dependencies: ["SapientKit"]),
    ]
)
