import Foundation
import Nebula
import NIO

// Start a LoadBalanceAmas server
let amasAddress = try SocketAddress(ipAddress: "::1", port: 8001)
let amas = LoadBalanceAmas(name: "ml-amas", namespace: "production.ml")
let server = try await NMTServer.bind(on: amasAddress, delegate: amas)

// Register with Galaxy
let galaxyAddress = try SocketAddress(ipAddress: "::1", port: 9000)
let galaxyClient = try await NMTClient.connect(to: galaxyAddress)
try await galaxyClient.register(astral: amas, listeningOn: amasAddress)

print("Amas '\(await amas.name)' listening on \(amasAddress)")
try await server.listen()
