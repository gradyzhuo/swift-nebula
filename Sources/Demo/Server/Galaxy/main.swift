import Foundation
import Nebula
import NIO

let address = try SocketAddress(ipAddress: "::1", port: 9000)
let galaxy = StandardGalaxy(name: "nebula")
let server = try await NMTServer.bind(on: address, delegate: galaxy)
print("Galaxy listening on \(address)")
try await server.listen()
