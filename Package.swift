// swift-tools-version:6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-nebula",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "Nebula",
            targets: ["Nebula"]),
    ],
    dependencies: [
        .package(path: "/Users/gradyzhuo/Dropbox/Work/OpenSource/swift-nmtp"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.40.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.26.0"),
    ],
    targets: [
        .target(
            name: "Nebula",
            dependencies: [
                .product(name: "NMTP", package: "swift-nmtp"),
                .product(name: "NIO", package: "swift-nio"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NIOSSL", package: "swift-nio-ssl"),
            ]),
        .testTarget(
            name: "NebulaTests",
            dependencies: [
                "Nebula",
                .product(name: "NIOEmbedded", package: "swift-nio"),
            ]),
    ]
)
