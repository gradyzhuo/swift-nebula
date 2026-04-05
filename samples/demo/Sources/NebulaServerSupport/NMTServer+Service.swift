import Logging
import NMTP
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
