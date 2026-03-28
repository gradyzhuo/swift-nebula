import Foundation
import Nebula
import NebulaServiceLifecycle
import NIO
import ServiceLifecycle
import Logging

let galaxyHost = ProcessInfo.processInfo.environment["GALAXY_HOST"] ?? "0.0.0.0"
let galaxyPort = Int(ProcessInfo.processInfo.environment["GALAXY_PORT"] ?? "9001")!
let galaxyName = ProcessInfo.processInfo.environment["GALAXY_NAME"] ?? "production"

let ingressHost = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "127.0.0.1"
let ingressPort = Int(ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "2240")!

// Bind Galaxy
let galaxy = try StandardGalaxy(name: galaxyName)
let galaxyServer = try await Nebula.server(with: galaxy)
    .bind(on: SocketAddress(ipAddress: galaxyHost, port: galaxyPort))

// Register with Ingress
let ingressClient = try await NMTClient.connect(
    to: SocketAddress(ipAddress: ingressHost, port: ingressPort),
    as: .ingress
)
try await ingressClient.registerGalaxy(
    name: galaxyName,
    address: galaxyServer.address,
    identifier: galaxy.identifier
)

let logger = Logger(label: "nebula-galaxy")

let serviceGroup = ServiceGroup(
    services: [galaxyServer],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)

print("Galaxy '\(galaxyName)' listening on \(galaxyHost):\(galaxyPort), registered with Ingress")
try await serviceGroup.run()
