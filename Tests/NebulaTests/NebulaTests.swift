import Testing
import Foundation
import NIO
import NMTP
@testable import Nebula

// MARK: - Test Support

/// Collects labelled call events so middleware order can be asserted.
actor CallLog {
    var entries: [String] = []
    func record(_ s: String) { entries.append(s) }
}

/// Middleware that records when it runs (before and after calling next).
struct TrackingMiddleware: NMTMiddleware {
    let label: String
    let log: CallLog

    func handle(_ matter: Matter, next: NMTMiddlewareNext) async throws -> Matter? {
        await log.record("\(label):in")
        let result = try await next(matter)
        await log.record("\(label):out")
        return result
    }
}

/// Middleware that never calls next — simulates an auth gate that blocks the request.
struct ShortCircuitMiddleware: NMTMiddleware {
    func handle(_ matter: Matter, next: NMTMiddlewareNext) async throws -> Matter? {
        return nil
    }
}

private func loopbackPort0() throws -> SocketAddress {
    try .makeAddressResolvingHost("127.0.0.1", port: 0)
}

private func dummyChannel() -> Channel {
    EmbeddedChannel()
}

// MARK: - Suite 1: Middleware Chain (unit — no network)

@Suite("NMTMiddleware Chain")
struct NMTMiddlewareChainTests {

    private func echoStellar() throws -> ServiceStellar {
        let stellar = try ServiceStellar(name: "echo", namespace: "test.echo")
        let svc = Service(name: "echo")
        svc.add(method: "ping") { _ in Data([1]) }
        stellar.add(service: svc)
        return stellar
    }

    private func callMatter() throws -> Matter {
        let body = CallBody(namespace: "test.echo", service: "echo", method: "ping", arguments: [])
        return try Matter.make(type: .call, body: body)
    }

    /// With no middleware, a call matter is dispatched directly to coreDispatch.
    @Test func noMiddleware_callReachesCore() async throws {
        let stellar = try echoStellar()
        let reply = try await stellar.handle(matter: try callMatter(), channel: dummyChannel())
        let body = try #require(reply).decodeBody(CallReplyBody.self)
        #expect(body.error == nil)
        #expect(body.result != nil)
    }

    /// The last `use()` call becomes the outermost layer: B wraps A wraps core.
    /// Expected log: B:in → A:in → (core) → A:out → B:out
    @Test func lastRegistered_runsOutermost() async throws {
        let log = CallLog()
        let stellar = try echoStellar()
        stellar
            .use(TrackingMiddleware(label: "A", log: log))
            .use(TrackingMiddleware(label: "B", log: log))
        _ = try await stellar.handle(matter: try callMatter(), channel: dummyChannel())
        let entries = await log.entries
        #expect(entries == ["B:in", "A:in", "A:out", "B:out"])
    }

    /// A middleware that does not call `next` prevents all inner layers from running.
    @Test func shortCircuit_preventsInnerMiddleware() async throws {
        let log = CallLog()
        let stellar = try echoStellar()
        stellar
            .use(TrackingMiddleware(label: "A", log: log))
            .use(ShortCircuitMiddleware())
        _ = try await stellar.handle(matter: try callMatter(), channel: dummyChannel())
        #expect(await log.entries.isEmpty)
    }

    /// Non-call matters (clone) pass through the middleware chain and are handled by coreDispatch.
    @Test func nonCallMatter_cloneHandledByCore() async throws {
        let log = CallLog()
        let stellar = try echoStellar()
        stellar.use(TrackingMiddleware(label: "A", log: log))
        let cloneMatter = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await stellar.handle(matter: cloneMatter, channel: dummyChannel())
        let body = try #require(reply).decodeBody(CloneReplyBody.self)
        #expect(body.name == "echo")
        #expect(await log.entries == ["A:in", "A:out"])
    }
}

// MARK: - Suite 2: Ingress Routing (integration)

@Suite("Ingress Routing")
struct IngressRoutingTests {

    private func bindEchoStellar(namespace: String) async throws -> NMTServer {
        let stellar = try ServiceStellar(name: "echo", namespace: namespace)
        let svc = Service(name: "echo")
        svc.add(method: "ping") { _ in Data([1]) }
        stellar.add(service: svc)
        return try await NMTServer.bind(on: try loopbackPort0(), handler: stellar)
    }

    /// Planet-side `find` via Ingress → Galaxy → Amas returns a Stellar address.
    @Test func find_returnsStellarAddress() async throws {
        let galaxy = try StandardGalaxy(name: "test")
        let galaxyServer = try await NMTServer.bind(on: try loopbackPort0(), handler: galaxy)
        defer { Task { try? await galaxyServer.stop() } }

        let stellarServer = try await bindEchoStellar(namespace: "test.echo")
        defer { Task { try? await stellarServer.stop() } }

        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellarServer.address)

        let ingress = StandardIngress(name: "ingress")
        let ingressServer = try await NMTServer.bind(on: try loopbackPort0(), handler: ingress)
        defer { Task { try? await ingressServer.stop() } }

        let ingressClient = try await IngressClient.connect(to: ingressServer.address)
        try await ingressClient.registerGalaxy(
            name: "test",
            address: galaxyServer.address,
            identifier: galaxy.identifier
        )

        let result = try await ingressClient.find(namespace: "test.echo")
        #expect(result.stellarAddress != nil)
    }

    /// `unregister` via Ingress → Galaxy → Amas removes the dead Stellar and returns the next one.
    @Test func unregister_removesDeadStellarAndReturnsNext() async throws {
        let galaxy = try StandardGalaxy(name: "test")
        let galaxyServer = try await NMTServer.bind(on: try loopbackPort0(), handler: galaxy)
        defer { Task { try? await galaxyServer.stop() } }

        let stellar1Server = try await bindEchoStellar(namespace: "test.echo")
        defer { Task { try? await stellar1Server.stop() } }
        let stellar2Server = try await bindEchoStellar(namespace: "test.echo")
        defer { Task { try? await stellar2Server.stop() } }

        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellar1Server.address)
        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellar2Server.address)

        let ingress = StandardIngress(name: "ingress")
        let ingressServer = try await NMTServer.bind(on: try loopbackPort0(), handler: ingress)
        defer { Task { try? await ingressServer.stop() } }

        let ingressClient = try await IngressClient.connect(to: ingressServer.address)
        try await ingressClient.registerGalaxy(
            name: "test",
            address: galaxyServer.address,
            identifier: galaxy.identifier
        )

        let first = try await ingressClient.find(namespace: "test.echo")
        let firstAddr = try #require(first.stellarAddress)

        let next = try await ingressClient.unregister(
            namespace: "test.echo",
            host: firstAddr.ipAddress ?? "127.0.0.1",
            port: firstAddr.port ?? 0
        )

        let nextAddr = try #require(next.nextAddress)
        #expect(nextAddr != firstAddr)
    }
}
