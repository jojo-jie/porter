// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Porter",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Porter", targets: ["PorterApp"]),
        .executable(name: "PorterPathValidation", targets: ["PorterPathValidation"])
    ],
    targets: [
        .target(name: "PorterCore"),
        .executableTarget(
            name: "PorterApp",
            dependencies: ["PorterCore"]
        ),
        .executableTarget(
            name: "PorterPathValidation",
            dependencies: ["PorterCore"]
        )
    ]
)
