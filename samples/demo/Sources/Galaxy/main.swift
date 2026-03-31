import Foundation
import Nebula
import NebulaServiceLifecycle
import NIO
import ServiceLifecycle
import Logging

let galaxyHost = ProcessInfo.processInfo.environment["GALAXY_HOST"] ?? "0.0.0.0"
let galaxyPort = Int(ProcessInfo.processInfo.environment["GALAXY_PORT"] ?? "62200")!
let galaxyName = ProcessInfo.processInfo.environment["GALAXY_NAME"] ?? "production"
// GALAXY_ADVERTISE_HOST: the hostname Ingress should use to reach this Galaxy.
// Set to the Docker service name (e.g. "galaxy") when running in docker-compose.
let galaxyAdvertiseHost = ProcessInfo.processInfo.environment["GALAXY_ADVERTISE_HOST"] ?? galaxyHost

let ingressHost = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "127.0.0.1"
let ingressPort = Int(ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "6224")!

// Bind Galaxy
let galaxy = try StandardGalaxy(name: galaxyName)
let galaxyServer = try await Nebula.server(with: galaxy)
    .bind(on: SocketAddress(ipAddress: galaxyHost, port: galaxyPort))

// Register with Ingress using the advertised host so Ingress can reach us.
let advertiseAddress = try SocketAddress.makeAddressResolvingHost(
    galaxyAdvertiseHost, port: galaxyServer.address.port ?? galaxyPort
)
let ingressClient = try await NMTClient.connect(
    to: try SocketAddress.makeAddressResolvingHost(ingressHost, port: ingressPort),
    as: .ingress
)
try await ingressClient.registerGalaxy(
    name: galaxyName,
    address: advertiseAddress,
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
