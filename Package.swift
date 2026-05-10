// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Porter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Porter", targets: ["PorterApp"])
    ],
    targets: [
        .executableTarget(name: "PorterApp")
    ]
)
