//
//  NMTServer+Service.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Logging
import Nebula
import ServiceLifecycle

extension NMTServer: ServiceLifecycle.Service {
    public func run() async throws {
        let logger = Logger(label: "nebula.nmt.server")
        try await withGracefulShutdownHandler {
            try await listen()
        } onGracefulShutdown: {
            logger.info("Interrupted. Shutting down \(self.address) ...")
            self.closeNow()
        }
    }
}
