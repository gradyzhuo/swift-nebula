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
        .executableTarget(
            name: "GalaxyServer",
            dependencies: ["Nebula"],
            path: "Sources/Demo/Server/Galaxy"),
        .executableTarget(
            name: "AmasServer",
            dependencies: ["Nebula"],
            path: "Sources/Demo/Server/Amas"),
        .executableTarget(
            name: "StellaireServer",
            dependencies: [
                "Nebula",
                .product(name: "MessagePacker", package: "MessagePacker"),
            ],
            path: "Sources/Demo/Server/Stellar"),
        .executableTarget(
            name: "AmasClient",
            dependencies: ["Nebula"],
            path: "Sources/Demo/Client/Amas"),
        .executableTarget(
            name: "GalaxyClient",
            dependencies: ["Nebula"],
            path: "Sources/Demo/Client/Galaxy"),
        .executableTarget(
            name: "StellaireClient",
            dependencies: ["Nebula"],
            path: "Sources/Demo/Client/Stellar"),
        .executableTarget(
            name: "PlanetClient",
            dependencies: ["Nebula"],
            path: "Sources/Demo/Planet"),
    ]
)
