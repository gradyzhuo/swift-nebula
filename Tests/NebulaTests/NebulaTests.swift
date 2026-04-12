// Tests/NebulaTests/NebulaTests.swift

import Testing
import Foundation
import NIO
import NMTP
import MessagePacker
@testable import Nebula

// MARK: - Test Support

actor CallLog {
    var entries: [String] = []
    func record(_ s: String) { entries.append(s) }
}

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

struct ShortCircuitMiddleware: NMTMiddleware {
    func handle(_ matter: Matter, next: NMTMiddlewareNext) async throws -> Matter? { nil }
}

private func loopbackPort0() throws -> SocketAddress {
    try .makeAddressResolvingHost("127.0.0.1", port: 0)
}

private func echoStellar() async throws -> ServiceStellar {
    let stellar = try ServiceStellar(name: "echo", namespace: "test.echo")
    let svc = Service(name: "echo")
    await svc.add(method: "ping") { _ in Data([1]) }
    await stellar.add(service: svc)
    return stellar
}

private func makeCallMatter() throws -> Matter {
    try Matter.make(CallMatter(namespace: "test.echo", service: "echo", method: "ping", arguments: []))
}

// MARK: - Suite 1: Middleware Chain (unit — no network)

@Suite("NMTMiddleware Chain")
struct NMTMiddlewareChainTests {

    @Test func noMiddleware_callReachesCore() async throws {
        let stellar = try await echoStellar()
        let reply = try await stellar.handle(matter: try makeCallMatter(), channel: EmbeddedChannel())
        let body = try #require(reply).decode(CallReplyMatter.self)
        #expect(body.error == nil)
        #expect(body.result != nil)
    }

    @Test func lastRegistered_runsOutermost() async throws {
        let log = CallLog()
        let stellar = try await echoStellar()
        await stellar.use(TrackingMiddleware(label: "A", log: log))
        await stellar.use(TrackingMiddleware(label: "B", log: log))
        _ = try await stellar.handle(matter: try makeCallMatter(), channel: EmbeddedChannel())
        let entries = await log.entries
        #expect(entries == ["B:in", "A:in", "A:out", "B:out"])
    }

    @Test func shortCircuit_preventsInnerMiddleware() async throws {
        let log = CallLog()
        let stellar = try await echoStellar()
        await stellar.use(TrackingMiddleware(label: "A", log: log))
        await stellar.use(ShortCircuitMiddleware())
        _ = try await stellar.handle(matter: try makeCallMatter(), channel: EmbeddedChannel())
        #expect(await log.entries.isEmpty)
    }

    @Test func nonCallMatter_cloneHandledByCore() async throws {
        let log = CallLog()
        let stellar = try await echoStellar()
        await stellar.use(TrackingMiddleware(label: "A", log: log))
        let cloneMatter = try Matter.make(CloneMatter())
        let reply = try await stellar.handle(matter: cloneMatter, channel: EmbeddedChannel())
        let body = try #require(reply).decode(CloneReplyMatter.self)
        #expect(body.name == "echo")
        #expect(await log.entries == ["A:in", "A:out"])
    }
}

// MARK: - Suite 2: Ingress Routing (integration)

@Suite("Ingress Routing", .serialized)
struct IngressRoutingTests {

    private func bindEchoStellar(namespace: String, group: MultiThreadedEventLoopGroup) async throws -> NMTServer {
        let stellar = try ServiceStellar(name: "echo", namespace: namespace)
        let svc = Service(name: "echo")
        await svc.add(method: "ping") { _ in Data([1]) }
        await stellar.add(service: svc)
        let dispatcher = NMTDispatcher()
        await stellar.register(on: dispatcher)
        return try await NMTServer.bind(on: try loopbackPort0(), handler: dispatcher, eventLoopGroup: group)
    }

    @Test func find_returnsStellarAddress() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let galaxy = try StandardGalaxy(name: "test")
        let galaxyDispatcher = NMTDispatcher()
        await galaxy.register(on: galaxyDispatcher)
        let galaxyServer = try await NMTServer.bind(on: try loopbackPort0(), handler: galaxyDispatcher, eventLoopGroup: group)

        let stellarServer = try await bindEchoStellar(namespace: "test.echo", group: group)
        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellarServer.address)

        let ingress = StandardIngress(name: "ingress")
        let ingressDispatcher = NMTDispatcher()
        await ingress.register(on: ingressDispatcher)
        let ingressServer = try await NMTServer.bind(on: try loopbackPort0(), handler: ingressDispatcher, eventLoopGroup: group)

        let ingressClient = try await IngressClient.connect(to: ingressServer.address, eventLoopGroup: group)
        try await ingressClient.registerGalaxy(
            name: "test",
            address: galaxyServer.address,
            identifier: galaxy.identifier
        )

        let result = try await ingressClient.find(namespace: "test.echo")
        #expect(result.stellarAddress != nil)

        try? await ingressClient.close()
        try? await ingressServer.stop()
        try? await stellarServer.stop()
        try? await galaxyServer.stop()
        try? await group.shutdownGracefully()
    }

    @Test func unregister_removesDeadStellarAndReturnsNext() async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
        let galaxy = try StandardGalaxy(name: "test")
        let galaxyDispatcher = NMTDispatcher()
        await galaxy.register(on: galaxyDispatcher)
        let galaxyServer = try await NMTServer.bind(on: try loopbackPort0(), handler: galaxyDispatcher, eventLoopGroup: group)

        let stellar1Server = try await bindEchoStellar(namespace: "test.echo", group: group)
        let stellar2Server = try await bindEchoStellar(namespace: "test.echo", group: group)

        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellar1Server.address)
        try await galaxy.register(namespace: "test.echo", stellarEndpoint: stellar2Server.address)

        let ingress = StandardIngress(name: "ingress")
        let ingressDispatcher = NMTDispatcher()
        await ingress.register(on: ingressDispatcher)
        let ingressServer = try await NMTServer.bind(on: try loopbackPort0(), handler: ingressDispatcher, eventLoopGroup: group)

        let ingressClient = try await IngressClient.connect(to: ingressServer.address, eventLoopGroup: group)
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

        try? await ingressClient.close()
        try? await ingressServer.stop()
        try? await stellar1Server.stop()
        try? await stellar2Server.stop()
        try? await galaxyServer.stop()
        try? await group.shutdownGracefully()
    }
}

// MARK: - Suite 3: Service actor

@Suite("Service Actor")
struct ServiceActorTests {

    @Test func concurrentHandleCalls() async throws {
        let stellar = try await echoStellar()
        let matter = try makeCallMatter()

        try await withThrowingTaskGroup(of: Matter?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    try await stellar.handle(matter: matter, channel: EmbeddedChannel())
                }
            }
            for try await reply in group {
                let body = try #require(reply).decode(CallReplyMatter.self)
                #expect(body.error == nil)
            }
        }
    }

    @Test func concurrentAddAndPerform() async throws {
        let svc = Service(name: "math")
        await svc.add(method: "double") { args in
            guard let first = args.first else { return nil }
            let n = try first.unwrap(as: Int.self)
            return try MessagePackEncoder().encode(n * 2)
        }

        try await withThrowingTaskGroup(of: Data?.self) { group in
            for _ in 0..<20 {
                group.addTask {
                    let arg = try Argument.wrap(key: "x", value: 1)
                    return try await svc.perform(method: "double", with: [arg])
                }
            }
            for try await result in group {
                let value = try MessagePackDecoder().decode(Int.self, from: result!)
                #expect(value == 2)
            }
        }
    }
}
