import Foundation
import Nebula
import NebulaServiceLifecycle
import NIO
import ServiceLifecycle
import Logging

let host = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "0.0.0.0"
let port = Int(ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "2240")!

let ingress = StandardIngress(name: "ingress")
let server = try await Nebula.server(with: ingress)
    .bind(on: SocketAddress(ipAddress: host, port: port))

let logger = Logger(label: "nebula-ingress")

let serviceGroup = ServiceGroup(
    services: [server],
    gracefulShutdownSignals: [.sigterm, .sigint],
    logger: logger
)

print("Ingress listening on \(host):\(port)")
try await serviceGroup.run()
