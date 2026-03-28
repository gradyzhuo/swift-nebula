import Foundation
import Nebula
import NebulaServiceLifecycle
import NIO
import ServiceLifecycle
import Logging
import MessagePacker

let stellarHost = ProcessInfo.processInfo.environment["STELLAR_HOST"] ?? "0.0.0.0"
let stellarPort = Int(ProcessInfo.processInfo.environment["STELLAR_PORT"] ?? "7000")!
let stellarName = ProcessInfo.processInfo.environment["STELLAR_NAME"] ?? "Embedding"
let namespace = ProcessInfo.processInfo.environment["STELLAR_NAMESPACE"] ?? "production.ml.embedding"

let galaxyHost = ProcessInfo.processInfo.environment["GALAXY_HOST"] ?? "127.0.0.1"
let galaxyPort = Int(ProcessInfo.processInfo.environment["GALAXY_PORT"] ?? "9001")!

// Define Stellar and its services
let stellar = try ServiceStellar(name: stellarName, namespace: namespace)

let w2v = Service(name: "w2v")
w2v.add(method: "wordVector") { args in
    print("[Stellar] wordVector called with:", args.toDictionary())
    let result = ["vector": [0.1, 0.2, 0.3]]
    return try MessagePackEncoder().encode(result)
}
stellar.add(service: w2v)

// Bind Stellar
let stellarServer = try await Nebula.server(with: stellar)
    .bind(on: SocketAddress(ipAddress: stellarHost, port: stellarPort))

// Register with Galaxy
let galaxyClient = try await NMTClient.connect(
    to: SocketAddress(ipAddress: galaxyHost, port: galaxyPort),
    as: .galaxy
)
try await galaxyClient.register(astral: stellar, listeningOn: stellarServer.address)

let logger = Logger(label: "nebula-stellar")

let serviceGroup = ServiceGroup(
    services: [stellarServer],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)

print("Stellar '\(stellarName)' (\(namespace)) listening on \(stellarHost):\(stellarPort), registered with Galaxy")
try await serviceGroup.run()
