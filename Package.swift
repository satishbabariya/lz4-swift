// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "lz4-swift",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "lz4-swift",
            targets: ["lz4-swift"]
        ),
        .executable(
            name: "lz4-swift-cli",
            targets: ["lz4-swift-cli"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "lz4-swift"
        ),
        .executableTarget(
            name: "lz4-swift-cli",
            dependencies: ["lz4-swift"]
        ),
        .testTarget(
            name: "lz4-swiftTests",
            dependencies: ["lz4-swift"]
        ),
    ]
)
