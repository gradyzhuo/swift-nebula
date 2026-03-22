//
//  DemoTask.swift
//
//  Runs a sample Planet call after the servers are up,
//  then keeps running until Ctrl+C triggers graceful shutdown.
//

import Foundation
import Nebula
import NIO
import ServiceLifecycle

struct DemoTask: ServiceLifecycle.Service {
    let galaxyAddress: SocketAddress

    func run() async throws {
        // Give servers a moment to finish binding
        try await Task.sleep(for: .milliseconds(300))

        print("\n── Nebula Demo Call ──")

        let planet = try await Nebula.planet(name: "demo-planet", connectingTo: galaxyAddress)

        let result = try await planet.call(
            namespace: "production.ml.embedding",
            service: "w2v",
            method: "wordVector",
            arguments: [try Argument.wrap(key: "words", value: ["慢跑", "反光", "排汗", "乾爽"])]
        )

        print("Result:", result as Any)
        print("── Press Ctrl+C to stop ──\n")

        // Block until the ServiceGroup cancels this task (Ctrl+C / SIGTERM)
        try await Task.sleep(for: .seconds(60 * 60 * 24))
    }
}
