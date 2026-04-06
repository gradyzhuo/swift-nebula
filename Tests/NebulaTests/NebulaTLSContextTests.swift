// Tests/NebulaTests/NebulaTLSContextTests.swift
import Testing
import Foundation
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
