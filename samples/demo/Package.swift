// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "nebula-demo",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/hirotakan/MessagePacker.git", from: "0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "NebulaDemo",
            dependencies: [
                .product(name: "Nebula", package: "swift-nebula"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MessagePacker", package: "MessagePacker"),
            ],
            path: "Sources/NebulaDemo"
        ),
    ]
)
