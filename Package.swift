// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-nebula",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "Nebula",
            targets: ["Nebula"]),
        .library(
            name: "NebulaServiceLifecycle",
            targets: ["NebulaServiceLifecycle"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.40.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.10.0"),
        .package(url: "https://github.com/hirotakan/MessagePacker.git", from: "0.4.0"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "Nebula",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "MessagePacker", package: "MessagePacker"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        .target(
            name: "NebulaServiceLifecycle",
            dependencies: [
                "Nebula",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        .testTarget(
            name: "NebulaTests",
            dependencies: ["Nebula"]),
    ]
)
