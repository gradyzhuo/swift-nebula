import Foundation
import NebulaClient

let ingressHost = ProcessInfo.processInfo.environment["INGRESS_HOST"] ?? "127.0.0.1"
let ingressPort = ProcessInfo.processInfo.environment["INGRESS_PORT"] ?? "6224"

struct VectorResult: Decodable {
    let vector: [Float]
}

print("[Client] Connecting to Ingress \(ingressHost):\(ingressPort) ...")
let planet = try await NebulaClient.planet(
    connecting: "nmtp://\(ingressHost):\(ingressPort)/production/ml/embedding",
    service: "w2v"
)
print("[Client] Connected. Calling wordVector ...")

let result = try await planet.call(
    method: "wordVector",
    arguments: [
        .wrap(key: "words", value: ["慢跑", "反光", "排汗", "乾爽"])
    ],
    as: VectorResult.self
)

print("Result:", result.vector)
