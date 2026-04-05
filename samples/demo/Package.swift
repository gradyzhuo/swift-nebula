// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "nebula-demo",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(path: "../.."),
        .package(path: "../../../swift-nmtp"),
        .package(path: "../../../swift-nebula-client"),
        .package(url: "https://github.com/swift-server/swift-service-lifecycle.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/hirotakan/MessagePacker.git", from: "0.4.0"),
    ],
    targets: [
        // Shared helper: NMTServer + ServiceLifecycle.Service conformance
        .target(
            name: "NebulaServerSupport",
            dependencies: [
                .product(name: "Nebula", package: "swift-nebula"),
                .product(name: "NMTP", package: "swift-nmtp"),
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "Ingress",
            dependencies: [
                "NebulaServerSupport",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "Galaxy",
            dependencies: [
                "NebulaServerSupport",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .executableTarget(
            name: "Stellar",
            dependencies: [
                "NebulaServerSupport",
                .product(name: "ServiceLifecycle", package: "swift-service-lifecycle"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "MessagePacker", package: "MessagePacker"),
            ]
        ),
        .executableTarget(
            name: "Client",
            dependencies: [
                .product(name: "NebulaClient", package: "swift-nebula-client"),
                .product(name: "MessagePacker", package: "MessagePacker"),
            ]
        ),
        .executableTarget(
            name: "CometDemo",
            dependencies: [
                .product(name: "NebulaClient", package: "swift-nebula-client"),
            ]
        ),
        .executableTarget(
            name: "SatelliteDemo",
            dependencies: [
                .product(name: "NebulaClient", package: "swift-nebula-client"),
            ]
        ),
    ]
)
