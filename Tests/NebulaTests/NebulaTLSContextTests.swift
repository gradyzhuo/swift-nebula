// Tests/NebulaTests/NebulaTLSContextTests.swift
import Testing
import Foundation
import NIO
import NMTP
@testable import Nebula

/// Resolves the path to Tests/Fixtures/ relative to this source file.
private func fixturesPath() -> String {
    URL(fileURLWithPath: #filePath)       // NebulaTLSContextTests.swift
        .deletingLastPathComponent()      // NebulaTests/
        .deletingLastPathComponent()      // Tests/
        .appendingPathComponent("Fixtures")
        .path
}

@Suite("NebulaTLSContext")
struct NebulaTLSContextTests {

    private func serverConfig() -> NebulaTLSConfiguration {
        let p = fixturesPath()
        return NebulaTLSConfiguration(
            ca: .file(path: "\(p)/ca.crt"),
            identity: .files(cert: "\(p)/server.crt", key: "\(p)/server.key")
        )
    }

    private func clientConfig() -> NebulaTLSConfiguration {
        let p = fixturesPath()
        return NebulaTLSConfiguration(
            ca: .file(path: "\(p)/ca.crt"),
            identity: .files(cert: "\(p)/client.crt", key: "\(p)/client.key")
        )
    }

    // MARK: - TLSConfiguration types

    @Test func caSource_file_storesPath() {
        let src = CACertificateSource.file(path: "/tmp/ca.crt")
        guard case .file(let path) = src else { Issue.record("expected .file"); return }
        #expect(path == "/tmp/ca.crt")
    }

    @Test func identitySource_files_storesCertAndKey() {
        let src = IdentitySource.files(cert: "/tmp/cert.crt", key: "/tmp/key.key")
        guard case .files(let cert, let key) = src else { Issue.record("expected .files"); return }
        #expect(cert == "/tmp/cert.crt")
        #expect(key == "/tmp/key.key")
    }

    // MARK: - Init

    @Test func init_withFilePaths_succeeds() throws {
        _ = try NebulaTLSContext(configuration: serverConfig())
    }

    @Test func init_withInMemoryPEM_succeeds() throws {
        let p = fixturesPath()
        let caCert = try Data(contentsOf: URL(fileURLWithPath: "\(p)/ca.crt"))
        let serverCert = try Data(contentsOf: URL(fileURLWithPath: "\(p)/server.crt"))
        let serverKey = try Data(contentsOf: URL(fileURLWithPath: "\(p)/server.key"))

        let config = NebulaTLSConfiguration(
            ca: .pem(caCert),
            identity: .pem(cert: serverCert, key: serverKey)
        )
        _ = try NebulaTLSContext(configuration: config)
    }

    @Test func init_withBadCertPath_throws() {
        let config = NebulaTLSConfiguration(
            ca: .file(path: "/nonexistent/ca.crt"),
            identity: .files(cert: "/nonexistent/server.crt", key: "/nonexistent/server.key")
        )
        #expect(throws: (any Error).self) {
            try NebulaTLSContext(configuration: config)
        }
    }

    // MARK: - Hot reload

    @Test func reload_replacesContext() async throws {
        let ctx = try NebulaTLSContext(configuration: serverConfig())

        // Capture the server handler before reload.
        let handlerBefore = try await ctx.makeServerHandler()

        // Reload with the same config (in production, this would be new certs).
        try ctx.reload(configuration: serverConfig())

        // The new handler is a freshly constructed object.
        let handlerAfter = try await ctx.makeServerHandler()

        // Both handlers are valid ChannelHandlers — we just verify they are distinct objects.
        // (NIOSSLServerHandler does not conform to Equatable, so we use ObjectIdentifier.)
        #expect(
            ObjectIdentifier(handlerBefore as AnyObject) !=
            ObjectIdentifier(handlerAfter as AnyObject)
        )
    }

    @Test func reload_withBadConfig_doesNotCorruptExistingContext() async throws {
        let ctx = try NebulaTLSContext(configuration: serverConfig())

        // A reload with invalid paths should throw without corrupting ctx.
        let badConfig = NebulaTLSConfiguration(
            ca: .file(path: "/bad/ca.crt"),
            identity: .files(cert: "/bad/server.crt", key: "/bad/server.key")
        )
        #expect(throws: (any Error).self) {
            try ctx.reload(configuration: badConfig)
        }

        // ctx must still work after failed reload.
        _ = try await ctx.makeServerHandler()
    }
}

@Suite("TLS Forwarding")
struct TLSForwardingTests {

    private func serverConfig() -> NebulaTLSConfiguration {
        let p = fixturesPath()
        return NebulaTLSConfiguration(
            ca: .file(path: "\(p)/ca.crt"),
            identity: .files(cert: "\(p)/server.crt", key: "\(p)/server.key")
        )
    }

    private func clientConfig() -> NebulaTLSConfiguration {
        let p = fixturesPath()
        return NebulaTLSConfiguration(
            ca: .file(path: "\(p)/ca.crt"),
            identity: .files(cert: "\(p)/client.crt", key: "\(p)/client.key")
        )
    }

    /// Verify that passing a non-nil NebulaTLSContext to GalaxyClient.connect
    /// actually activates TLS on the connection.
    /// A successful roundtrip with a TLS server proves the tls parameter is
    /// forwarded to the underlying NMTClient (a plain client cannot handshake
    /// with a TLS server).
    @Test func galaxyClient_withTLS_activatesTLSOnConnect() async throws {
        let serverTLS = try NebulaTLSContext(configuration: serverConfig())
        let clientTLS = try NebulaTLSContext(configuration: clientConfig())

        let server = try await NMTServer.bind(
            on: try SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0),
            handler: EchoMatter(),
            tls: serverTLS
        )
        defer { Task { try? await server.shutdown() } }

        // GalaxyClient.connect must forward tls — confirmed by a successful
        // roundtrip with the TLS server.
        let client = try await GalaxyClient.connect(to: server.address, tls: clientTLS)
        defer { Task { try? await client.close() } }

        let matter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await client.request(matter: matter)
        #expect(reply.matterID == matter.matterID)
    }
}

private struct EchoMatter: NMTServerTarget {
    func handle(matter: Matter, channel: Channel) async throws -> Matter? {
        Matter(type: .reply, matterID: matter.matterID, body: matter.body)
    }
}

@Suite("mTLS Integration")
struct MTLSIntegrationTests {

    private func serverConfig() -> NebulaTLSConfiguration {
        let p = fixturesPath()
        return NebulaTLSConfiguration(
            ca: .file(path: "\(p)/ca.crt"),
            identity: .files(cert: "\(p)/server.crt", key: "\(p)/server.key")
        )
    }

    private func clientConfig() -> NebulaTLSConfiguration {
        let p = fixturesPath()
        return NebulaTLSConfiguration(
            ca: .file(path: "\(p)/ca.crt"),
            identity: .files(cert: "\(p)/client.crt", key: "\(p)/client.key")
        )
    }

    private func rogueClientConfig() -> NebulaTLSConfiguration {
        let p = fixturesPath()
        return NebulaTLSConfiguration(
            // Trusts the real CA (so the server cert verification passes)
            ca: .file(path: "\(p)/ca.crt"),
            // But presents a cert signed by the rogue CA (server will reject)
            identity: .files(
                cert: "\(p)/rogue-client.crt",
                key: "\(p)/rogue-client.key"
            )
        )
    }

    @Test func mTLS_handshake_succeeds() async throws {
        let serverTLS = try NebulaTLSContext(configuration: serverConfig())
        let clientTLS = try NebulaTLSContext(configuration: clientConfig())

        let server = try await NMTServer.bind(
            on: try SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0),
            handler: EchoMatter(),
            tls: serverTLS
        )
        defer { Task { try? await server.shutdown() } }

        let client = try await NMTClient.connect(to: server.address, tls: clientTLS)
        defer { Task { try? await client.close() } }

        let matter = Matter(type: .call, body: Data("hello-mtls".utf8))
        let reply = try await client.request(matter: matter)
        #expect(reply.matterID == matter.matterID)
        #expect(reply.type == .reply)
    }

    @Test func mTLS_rejectsUnknownClientCert() async throws {
        let serverTLS = try NebulaTLSContext(configuration: serverConfig())
        let rogueTLS = try NebulaTLSContext(configuration: rogueClientConfig())

        let server = try await NMTServer.bind(
            on: try SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0),
            handler: EchoMatter(),
            tls: serverTLS
        )
        defer { Task { try? await server.shutdown() } }

        // The TLS handshake will fail because the rogue cert is not signed by the server's CA.
        // Issue.record fires if no error is thrown (meaning the rogue cert was wrongly accepted).
        // Any caught error means the rogue cert was correctly rejected — that is the passing path.
        do {
            let client = try await NMTClient.connect(to: server.address, tls: rogueTLS)
            let matter = Matter(type: .call, body: Data())
            _ = try await client.request(matter: matter)
            Issue.record("Expected TLS handshake failure — connection should have been rejected")
        } catch {
            // Rogue cert rejected as expected (NIOSSLError or connectionClosed from server close).
        }
    }

    @Test func mTLS_existingConnectionSurvivesReload() async throws {
        let serverTLS = try NebulaTLSContext(configuration: serverConfig())
        let clientTLS = try NebulaTLSContext(configuration: clientConfig())

        let server = try await NMTServer.bind(
            on: try SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 0),
            handler: EchoMatter(),
            tls: serverTLS
        )
        defer { Task { try? await server.shutdown() } }

        let client = try await NMTClient.connect(to: server.address, tls: clientTLS)
        defer { Task { try? await client.close() } }

        // Confirm the connection works before reload.
        let before = Matter(type: .call, body: Data("before-reload".utf8))
        let reply1 = try await client.request(matter: before)
        #expect(reply1.type == .reply)

        // Reload with the same certs (simulating cert rotation).
        try serverTLS.reload(configuration: serverConfig())

        // Existing connection must still be usable after reload.
        let after = Matter(type: .call, body: Data("after-reload".utf8))
        let reply2 = try await client.request(matter: after)
        #expect(reply2.type == .reply)
    }
}
