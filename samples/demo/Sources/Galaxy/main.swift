import Foundation
import Nebula
import NebulaServerSupport
import NIO
import ServiceLifecycle
import Logging

LoggingSystem.bootstrap(ColorLogHandler.init)

let logger = Logger(label: "nebula.galaxy")
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
let galaxyServer = try await Nebula.bind(galaxy, on: SocketAddress(ipAddress: galaxyHost, port: galaxyPort))

// Register with Ingress using the advertised host so Ingress can reach us.
let advertiseAddress = try SocketAddress.makeAddressResolvingHost(
    galaxyAdvertiseHost, port: galaxyServer.address.port ?? galaxyPort
)
let ingressClient = try await IngressClient.connect(
    to: try SocketAddress.makeAddressResolvingHost(ingressHost, port: ingressPort)
)
try await ingressClient.registerGalaxy(
    name: galaxyName,
    address: advertiseAddress,
    identifier: galaxy.identifier
)

logger.info("Galaxy '\(galaxyName)' listening on \(galaxyHost):\(galaxyPort), registered with Ingress")

let serviceGroup = ServiceGroup(
    services: [galaxyServer],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)
try await serviceGroup.run()
