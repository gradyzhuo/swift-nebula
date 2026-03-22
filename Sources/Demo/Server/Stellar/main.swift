import Foundation
import Nebula
import NIO
import MessagePacker

// 1. Define service
let stellar = ServiceStellar(name: "Embedding", namespace: "production.ml.embedding")

let w2v = Service(name: "w2v")
w2v.add(method: "wordVector") { args in
    print("wordVector called with:", args.toDictionary())
    let result = ["vector": [0.1, 0.2, 0.3]]
    return try MessagePackEncoder().encode(result)
}
stellar.add(service: w2v)

// 2. Start Stellar server
let stellarAddress = try SocketAddress(ipAddress: "::1", port: 7000)
let server = try await NMTServer.bind(on: stellarAddress, delegate: stellar)

// 3. Register with Amas
let amasAddress = try SocketAddress(ipAddress: "::1", port: 8001)
let amasClient = try await NMTClient.connect(to: amasAddress)
try await amasClient.register(astral: stellar, listeningOn: stellarAddress)

print("Stellar '\(stellar.name)' listening on \(stellarAddress)")
try await server.listen()
