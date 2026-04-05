import Foundation
import Nebula
import NebulaServerSupport
import NIO
import ServiceLifecycle
import Logging
import MessagePacker

LoggingSystem.bootstrap(ColorLogHandler.init)

let logger = Logger(label: "nebula.stellar")
let stellarHost = ProcessInfo.processInfo.environment["STELLAR_HOST"] ?? "0.0.0.0"
let stellarPort = Int(ProcessInfo.processInfo.environment["STELLAR_PORT"] ?? "62300")!
let stellarName = ProcessInfo.processInfo.environment["STELLAR_NAME"] ?? "Embedding"
let namespace = ProcessInfo.processInfo.environment["STELLAR_NAMESPACE"] ?? "production.ml.embedding"

let ingressHost = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "127.0.0.1"
let ingressPort = Int(ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "6224")!

let galaxyHost = ProcessInfo.processInfo.environment["GALAXY_HOST"] ?? "127.0.0.1"
let galaxyPort = Int(ProcessInfo.processInfo.environment["GALAXY_PORT"] ?? "62200")!

// Define Stellar and its services
let stellar = try ServiceStellar(name: stellarName, namespace: namespace)

let w2v = Service(name: "w2v")
w2v.add(method: "wordVector") { args in
    logger.info("wordVector called with: \(args.toDictionary())")
    let result = ["vector": [0.1, 0.2, 0.3]]
    return try MessagePackEncoder().encode(result)
}
stellar.add(service: w2v)

// Bind Stellar
let stellarServer = try await Nebula.bind(stellar, on: SocketAddress(ipAddress: stellarHost, port: stellarPort))

// Register with Galaxy
let galaxyClient = try await GalaxyClient.connect(
    to: try SocketAddress.makeAddressResolvingHost(galaxyHost, port: galaxyPort)
)
try await galaxyClient.register(astral: stellar, listeningOn: stellarServer.address)

logger.info("Stellar '\(stellarName)' (\(namespace)) listening on \(stellarHost):\(stellarPort), registered with Galaxy")

let serviceGroup = ServiceGroup(
    services: [stellarServer],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)
try await serviceGroup.run()
