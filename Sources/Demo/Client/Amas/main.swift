import Foundation
import Nebula
import NIO

let galaxyAddress = try SocketAddress(ipAddress: "::1", port: 9000)
let planet = try await Nebula.planet(name: "client", connectingTo: galaxyAddress)

let result = try await planet.call(
    namespace: "production.ml.embedding",
    service: "w2v",
    method: "wordVector",
    arguments: [try Argument.wrap(key: "words", value: ["慢跑", "反光", "排汗"])]
)

print("result:", result as Any)
