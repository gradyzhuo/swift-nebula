import Foundation
import Nebula
import NebulaServerSupport
import NIO
import ServiceLifecycle
import Logging

LoggingSystem.bootstrap(ColorLogHandler.init)

let logger = Logger(label: "nebula.ingress")
let host = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "0.0.0.0"
let port = Int(ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "6224")!

let ingress = StandardIngress(name: "ingress")
let server = try await Nebula.bind(ingress, on: SocketAddress(ipAddress: host, port: port))

logger.info("Ingress listening on \(host):\(port)")

let serviceGroup = ServiceGroup(
    services: [server],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)
try await serviceGroup.run()
