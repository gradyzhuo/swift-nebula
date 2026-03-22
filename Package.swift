// swift-tools-version:5.9
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
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.40.0"),
        .package(url: "https://github.com/apple/swift-nio-extras.git", from: "1.10.0"),
        .package(url: "https://github.com/hirotakan/MessagePacker.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "Nebula",
            dependencies: [
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "NIOExtras", package: "swift-nio-extras"),
                .product(name: "MessagePacker", package: "MessagePacker"),
            ]),
        .testTarget(
            name: "NebulaTests",
            dependencies: ["Nebula"]),
    ]
)
