import Foundation
import Nebula

let ingressHost = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "127.0.0.1"
let ingressPort = ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "2240"

struct VectorResult: Decodable {
    let vector: [Float]
}

let planet = try await Nebula.planet(
    connecting: "nmtp://\(ingressHost):\(ingressPort)/production/ml/embedding",
    service: "w2v"
)

let result = try await planet.call(
    method: "wordVector",
    arguments: [
        .wrap(key: "words", value: ["慢跑", "反光", "排汗", "乾爽"])
    ],
    as: VectorResult.self
)

print("Result:", result.vector)
