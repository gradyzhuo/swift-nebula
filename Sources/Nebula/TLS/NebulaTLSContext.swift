// Sources/Nebula/TLS/NebulaTLSContext.swift
import Foundation
import NIO
import NIOSSL
import Synchronization
import NMTP

/// Concrete `TLSContext` implementation backed by swift-nio-ssl (BoringSSL).
///
/// Satisfies DIP: `swift-nmtp` defines `TLSContext` (the abstraction);
/// `swift-nebula` owns the NIOSSL dependency and provides this implementation.
///
/// ## Thread Safety
/// `NebulaTLSContext` is a `final class` with `Mutex`-protected SSL contexts,
/// making it `Sendable` and safe to share across tasks.
///
/// ## Hot Reload
/// Call `reload(configuration:)` to rotate certificates without restarting.
/// Already-established connections are not interrupted — only new connections
/// use the updated certificate. This matches nginx/Envoy cert rotation behaviour.
/// On failure, the existing contexts are preserved unchanged.
///
/// ## mTLS
/// Both `makeServerHandler()` and `makeClientHandler()` install handlers that
/// present this node's identity certificate and verify the peer's certificate
/// against the configured CA. Any peer presenting a certificate not signed by
/// the CA is rejected during the TLS handshake.
public final class NebulaTLSContext: TLSContext {

    /// Mutex-protected server SSL context (shared across new inbound connections).
    private let serverCtxBox: Mutex<NIOSSLContext>
    /// Mutex-protected client SSL context (shared across new outbound connections).
    private let clientCtxBox: Mutex<NIOSSLContext>

    public init(configuration: NebulaTLSConfiguration) throws {
        let serverCtx = try NebulaTLSContext.buildServerContext(from: configuration)
        let clientCtx = try NebulaTLSContext.buildClientContext(from: configuration)
        self.serverCtxBox = Mutex(serverCtx)
        self.clientCtxBox = Mutex(clientCtx)
    }

    /// Rotate certificates. New connections use the updated contexts immediately.
    /// Throws if the new configuration contains invalid certificates.
    /// On failure, the existing contexts are preserved unchanged.
    public func reload(configuration: NebulaTLSConfiguration) async throws {
        let newServer = try NebulaTLSContext.buildServerContext(from: configuration)
        let newClient = try NebulaTLSContext.buildClientContext(from: configuration)
        serverCtxBox.withLock { $0 = newServer }
        clientCtxBox.withLock { $0 = newClient }
    }

    // MARK: - TLSContext

    public func makeServerHandler() async throws -> any ChannelHandler {
        let ctx = serverCtxBox.withLock { $0 }
        return try NIOSSLServerHandler(context: ctx)
    }

    public func makeClientHandler(serverHostname: String?) async throws -> any ChannelHandler {
        let ctx = clientCtxBox.withLock { $0 }
        return try NIOSSLClientHandler(context: ctx, serverHostname: serverHostname)
    }

    // MARK: - Private builders

    private static func buildServerContext(
        from config: NebulaTLSConfiguration
    ) throws -> NIOSSLContext {
        var tlsConfig = TLSConfiguration.makeServerConfiguration(
            certificateChain: try certChain(from: config.identity),
            privateKey: try privateKey(from: config.identity)
        )
        tlsConfig.trustRoots = .certificates(try caCerts(from: config.ca))
        // fullVerification requires a valid certificate chain from the peer.
        // Combined with trustRoots, this enforces mTLS: clients without a valid cert are rejected.
        tlsConfig.certificateVerification = .fullVerification
        return try NIOSSLContext(configuration: tlsConfig)
    }

    private static func buildClientContext(
        from config: NebulaTLSConfiguration
    ) throws -> NIOSSLContext {
        var tlsConfig = TLSConfiguration.makeClientConfiguration()
        tlsConfig.certificateChain = try certChain(from: config.identity)
        tlsConfig.privateKey = try privateKey(from: config.identity)
        tlsConfig.trustRoots = .certificates(try caCerts(from: config.ca))
        tlsConfig.certificateVerification = .fullVerification
        return try NIOSSLContext(configuration: tlsConfig)
    }

    // MARK: - Cert loading helpers

    private static func certChain(
        from source: IdentitySource
    ) throws -> [NIOSSLCertificateSource] {
        switch source {
        case .files(let cert, _):
            return [.file(cert)]
        case .pem(let certData, _):
            return try NIOSSLCertificate
                .fromPEMBytes(Array(certData))
                .map { .certificate($0) }
        }
    }

    private static func privateKey(
        from source: IdentitySource
    ) throws -> NIOSSLPrivateKeySource {
        switch source {
        case .files(_, let key):
            return .file(key)
        case .pem(_, let keyData):
            return .privateKey(
                try NIOSSLPrivateKey(bytes: Array(keyData), format: .pem))
        }
    }

    private static func caCerts(
        from source: CACertificateSource
    ) throws -> [NIOSSLCertificate] {
        switch source {
        case .file(let path):
            return try NIOSSLCertificate.fromPEMFile(path)
        case .pem(let data):
            return try NIOSSLCertificate.fromPEMBytes(Array(data))
        }
    }
}
