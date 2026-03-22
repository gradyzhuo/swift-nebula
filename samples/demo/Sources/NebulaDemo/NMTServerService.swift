//
//  NMTServerService.swift
//
//  Wraps NMTServer to conform to ServiceLifecycle.Service,
//  so it can participate in a ServiceGroup.
//

import Nebula
import ServiceLifecycle

struct NMTServerService: ServiceLifecycle.Service {
    let label: String
    let server: NMTServer

    func run() async throws {
        print("[\(label)] listening on \(server.address)")
        try await server.listen()
    }
}
