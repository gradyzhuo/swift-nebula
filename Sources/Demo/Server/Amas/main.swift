import Foundation
import Nebula
import NIO

// 1. Start Amas server
let amasAddress = try SocketAddress(ipAddress: "::1", port: 8001)
let amas = DirectAmas(name: "ml-amas", namespace: "production.ml")
let server = try await NMTServer.bind(on: amasAddress, delegate: amas)

// 2. Register with Galaxy
let galaxyAddress = try SocketAddress(ipAddress: "::1", port: 9000)
let galaxyClient = try await NMTClient.connect(to: galaxyAddress)
try await galaxyClient.register(astral: amas, listeningOn: amasAddress)

print("Amas '\(await amas.name)' listening on \(amasAddress)")
try await server.listen()
