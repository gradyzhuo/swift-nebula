//
//  DemoTask.swift
//
//  Runs a sample Planet call after the servers are up,
//  then keeps running until Ctrl+C triggers graceful shutdown.
//

import Foundation
import Nebula
import ServiceLifecycle

struct VectorResult: Decodable {
    let vector: [Float]
}

let planet = try await Nebula.planet(
    connecting: "nmtp://[::1]:22400/production/ml/embedding",
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
