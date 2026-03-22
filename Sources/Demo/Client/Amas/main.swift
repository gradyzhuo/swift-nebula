import Foundation
import Nebula
import NIO

let amasAddress = try SocketAddress(ipAddress: "::1", port: 8001)
let planet = try await Nebula.planet(name: "client", connecting: amasAddress)

let result = try await planet.call(
    namespace: "production.ml.embedding",
    service: "w2v",
    method: "wordVector",
    arguments: [try Argument.wrap(key: "words", value: ["慢跑", "反光", "排汗"])]
)

print("result:", result as Any)
