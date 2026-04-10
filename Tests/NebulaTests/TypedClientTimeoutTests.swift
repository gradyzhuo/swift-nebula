import Testing
import Foundation
import NIO
import NMTP
@testable import Nebula

/// Simulates a hung server: accepts the connection but never sends a reply.
private struct NeverReplyHandler: NMTServerTarget {
    func handle(matter: Matter, channel: any Channel) async throws -> Matter? {
        try await Task.sleep(for: .seconds(60))
        return nil
    }
}

@Suite("TypedClient timeout")
struct TypedClientTimeoutTests {

    /// Compile-only test: verifies that connect(defaultTimeout:) exists on all three clients.
    /// The connects are expected to fail at runtime (no server on port 1), so try? is used.
    @Test("connect(defaultTimeout:) parameter exists on all three clients")
    func connectAcceptsDefaultTimeout() async throws {
        let addr = try SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 1)
        _ = try? await GalaxyClient.connect(to: addr, defaultTimeout: .seconds(5))
        _ = try? await IngressClient.connect(to: addr, defaultTimeout: .seconds(5))
        _ = try? await StellarClient.connect(to: addr, defaultTimeout: .seconds(5))
    }

    @Test("GalaxyClient.find throws .timeout when server never replies (defaultTimeout)")
    func galaxyClientDefaultTimeoutFires() async throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer { Task { try? await elg.shutdownGracefully() } }

        let server = try await NMTServer.bind(
            on: .makeAddressResolvingHost("127.0.0.1", port: 0),
            handler: NeverReplyHandler()
        )
        defer { Task { await server.shutdown() } }

        let client = try await GalaxyClient.connect(
            to: server.address,
            defaultTimeout: .milliseconds(150),
            eventLoopGroup: elg
        )
        defer { Task { try? await client.close() } }

        await #expect(throws: NMTPError.timeout) {
            try await client.find(namespace: "test.never")
        }
    }

    @Test("per-method timeout overrides defaultTimeout")
    func perMethodTimeoutOverridesDefault() async throws {
        let elg = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        defer { Task { try? await elg.shutdownGracefully() } }

        let server = try await NMTServer.bind(
            on: .makeAddressResolvingHost("127.0.0.1", port: 0),
            handler: NeverReplyHandler()
        )
        defer { Task { await server.shutdown() } }

        // Long defaultTimeout — method-level override must win.
        let client = try await GalaxyClient.connect(
            to: server.address,
            defaultTimeout: .seconds(30),
            eventLoopGroup: elg
        )
        defer { Task { try? await client.close() } }

        await #expect(throws: NMTPError.timeout) {
            try await client.find(namespace: "test.never", timeout: .milliseconds(150))
        }
    }
}
