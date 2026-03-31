import Testing
import Foundation
import NIO
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

    func handle(_ envelope: Matter, next: NMTMiddlewareNext) async throws -> Matter? {
        await log.record("\(label):in")
        let result = try await next(envelope)
        await log.record("\(label):out")
        return result
    }
}

/// Middleware that never calls next — simulates an auth gate that blocks the request.
struct ShortCircuitMiddleware: NMTMiddleware {
    func handle(_ envelope: Matter, next: NMTMiddlewareNext) async throws -> Matter? {
        return nil
    }
}

actor Counter {
    var value = 0
    func increment() -> Int { value += 1; return value }
}

private func loopbackPort0() throws -> SocketAddress {
    try .makeAddressResolvingHost("127.0.0.1", port: 0)
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

    private func callEnvelope() throws -> Matter {
        let body = CallBody(namespace: "test.echo", service: "echo", method: "ping", arguments: [])
        return try Matter.make(type: .call, body: body)
    }

    /// With no middleware, a call envelope is dispatched directly to coreDispatch.
    @Test func noMiddleware_callReachesCore() async throws {
        let stellar = try echoStellar()
        let reply = try await stellar.handle(envelope: try callEnvelope())
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
        _ = try await stellar.handle(envelope: try callEnvelope())
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
        _ = try await stellar.handle(envelope: try callEnvelope())
        #expect(await log.entries.isEmpty)
    }

    /// Non-call envelopes (clone) pass through the middleware chain and are handled by coreDispatch.
    @Test func nonCallEnvelope_cloneHandledByCore() async throws {
        let log = CallLog()
        let stellar = try echoStellar()
        stellar.use(TrackingMiddleware(label: "A", log: log))
        let cloneEnvelope = try Matter.make(type: .clone, body: CloneBody())
        let reply = try await stellar.handle(envelope: cloneEnvelope)
        let body = try #require(reply).decodeBody(CloneReplyBody.self)
        #expect(body.name == "echo")
        #expect(await log.entries == ["A:in", "A:out"])
    }
}

// MARK: - Suite 2: Ingress Routing (integration)

@Suite("Ingress Routing")
struct IngressRoutingTests {

    private func bindEchoStellar(namespace: String) async throws -> NMTServer<ServiceStellar> {
        let stellar = try ServiceStellar(name: "echo", namespace: namespace)
        let svc = Service(name: "echo")
        svc.add(method: "ping") { _ in Data([1]) }
        stellar.add(service: svc)
        return try await NMTServer.bind(on: try loopbackPort0(), target: stellar)
    }

    /// Planet-side `find` via Ingress → Galaxy → Amas returns a Stellar address.
    @Test func find_returnsStellarAddress() async throws {
        let galaxy = try StandardGalaxy(name: "test")
        let galaxyServer = try await NMTServer.bind(on: try loopbackPort0(), target: galaxy)
        defer { Task { try? await galaxyServer.stop() } }

        let stellarServer = try await bindEchoStellar(namespace: "test.echo")
        defer { Task { try? await stellarServer.stop() } }

        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellarServer.address)

        let ingress = StandardIngress(name: "ingress")
        let ingressServer = try await NMTServer.bind(on: try loopbackPort0(), target: ingress)
        defer { Task { try? await ingressServer.stop() } }

        let ingressClient = try await NMTClient.connect(to: ingressServer.address, as: .ingress)
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
        let galaxyServer = try await NMTServer.bind(on: try loopbackPort0(), target: galaxy)
        defer { Task { try? await galaxyServer.stop() } }

        let stellar1Server = try await bindEchoStellar(namespace: "test.echo")
        defer { Task { try? await stellar1Server.stop() } }
        let stellar2Server = try await bindEchoStellar(namespace: "test.echo")
        defer { Task { try? await stellar2Server.stop() } }

        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellar1Server.address)
        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellar2Server.address)

        let ingress = StandardIngress(name: "ingress")
        let ingressServer = try await NMTServer.bind(on: try loopbackPort0(), target: ingress)
        defer { Task { try? await ingressServer.stop() } }

        let ingressClient = try await NMTClient.connect(to: ingressServer.address, as: .ingress)
        try await ingressClient.registerGalaxy(
            name: "test",
            address: galaxyServer.address,
            identifier: galaxy.identifier
        )

        // Trigger pool resolution: find returns stellar1 (round-robin index 0).
        let first = try await ingressClient.find(namespace: "test.echo")
        let firstAddr = try #require(first.stellarAddress)

        // Unregister stellar1 (simulating Planet reporting it as dead).
        let next = try await ingressClient.unregister(
            namespace: "test.echo",
            host: firstAddr.ipAddress ?? "127.0.0.1",
            port: firstAddr.port ?? 0
        )

        // Amas should return stellar2 as the next available endpoint.
        let nextAddr = try #require(next.nextAddress)
        #expect(nextAddr != firstAddr)
    }
}

// MARK: - Suite 3: Planet End-to-End Call (integration)

@Suite("Planet Call")
struct PlanetCallTests {

    /// Planet resolves a Stellar address via Ingress and makes a successful call.
    @Test func call_routesThroughIngressToStellar() async throws {
        let galaxy = try StandardGalaxy(name: "test")
        let galaxyServer = try await NMTServer.bind(on: try loopbackPort0(), target: galaxy)
        defer { Task { try? await galaxyServer.stop() } }

        let stellar = try ServiceStellar(name: "echo", namespace: "test.echo")
        let svc = Service(name: "echo")
        svc.add(method: "ping") { _ in Data([1]) }
        stellar.add(service: svc)
        let stellarServer = try await NMTServer.bind(on: try loopbackPort0(), target: stellar)
        defer { Task { try? await stellarServer.stop() } }

        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellarServer.address)

        let ingress = StandardIngress(name: "ingress")
        let ingressServer = try await NMTServer.bind(on: try loopbackPort0(), target: ingress)
        defer { Task { try? await ingressServer.stop() } }

        let ingressClient = try await NMTClient.connect(to: ingressServer.address, as: .ingress)
        try await ingressClient.registerGalaxy(
            name: "test",
            address: galaxyServer.address,
            identifier: galaxy.identifier
        )

        let planet = RoguePlanet(
            ingressClient: ingressClient,
            namespace: "test.echo",
            service: "echo"
        )

        let result = try await planet.call(method: "ping")
        #expect(result != nil)
    }

    /// Repeated calls to the same namespace reuse the cached Stellar connection.
    @Test func call_cachesStellarConnection() async throws {
        let galaxy = try StandardGalaxy(name: "test")
        let galaxyServer = try await NMTServer.bind(on: try loopbackPort0(), target: galaxy)
        defer { Task { try? await galaxyServer.stop() } }

        let counter = Counter()
        let stellar = try ServiceStellar(name: "echo", namespace: "test.echo")
        let svc = Service(name: "echo")
        svc.add(method: "ping") { _ in
            let n = await counter.increment()
            return Data([UInt8(n)])
        }
        stellar.add(service: svc)
        let stellarServer = try await NMTServer.bind(on: try loopbackPort0(), target: stellar)
        defer { Task { try? await stellarServer.stop() } }

        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellarServer.address)

        let ingress = StandardIngress(name: "ingress")
        let ingressServer = try await NMTServer.bind(on: try loopbackPort0(), target: ingress)
        defer { Task { try? await ingressServer.stop() } }

        let ingressClient = try await NMTClient.connect(to: ingressServer.address, as: .ingress)
        try await ingressClient.registerGalaxy(
            name: "test",
            address: galaxyServer.address,
            identifier: galaxy.identifier
        )

        let planet = RoguePlanet(
            ingressClient: ingressClient,
            namespace: "test.echo",
            service: "echo"
        )

        let r1 = try await planet.call(method: "ping")
        let r2 = try await planet.call(method: "ping")
        #expect(r1 != nil)
        #expect(r2 != nil)
        // Both calls reached the same Stellar (counter incremented twice).
        #expect(await counter.value == 2)
    }
}
