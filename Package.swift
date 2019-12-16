// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ComposableArchitecture",
    products: [
        .library(
            name: "ComposableArchitecture",
            targets: ["ComposableArchitecture"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ComposableArchitecture",
            dependencies: []),
        .testTarget(
            name: "ComposableArchitectureTests",
            dependencies: ["ComposableArchitecture"]),
    ]
)
