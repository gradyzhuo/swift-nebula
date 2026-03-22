import Foundation
import Nebula
import NIO
import ServiceLifecycle
import Logging

// MARK: - Galaxy

let galaxy = StandardGalaxy(name: "nebula")
let galaxyAddress = try SocketAddress(ipAddress: "::1", port: 9000)
let galaxyServer = try await NMTServer.bind(on: galaxyAddress, delegate: galaxy)

// MARK: - Stellar

let stellar = makeStellar()  // defined in StellarSetup.swift

let stellarAddress = try SocketAddress(ipAddress: "::1", port: 7000)
let stellarServer = try await NMTServer.bind(on: stellarAddress, delegate: stellar)

// Register with Galaxy — LoadBalanceAmas is created automatically
try await galaxy.register(namespace: stellar.namespace, stellarEndpoint: stellarAddress)

// MARK: - Run all services

let logger = Logger(label: "nebula-demo")

let serviceGroup = ServiceGroup(
    services: [
        NMTServerService(label: "Galaxy", server: galaxyServer),
        NMTServerService(label: "Stellar", server: stellarServer),
        DemoTask(galaxyAddress: galaxyAddress),
    ],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)

print("Starting Nebula demo (Ctrl+C to stop)...")
try await serviceGroup.run()
