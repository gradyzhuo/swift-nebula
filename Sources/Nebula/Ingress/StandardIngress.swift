// Sources/Nebula/Ingress/StandardIngress.swift

import Foundation
import NIO
import NMTP

public actor StandardIngress {
    public static let defaultPort: Int = 6224

    public let identifier: UUID
    public let name: String

    private var galaxyRegistry: [String: SocketAddress] = [:]
    private var galaxyClients: [String: GalaxyClient] = [:]
    private let tls: NebulaTLSContext?

    public init(name: String = "ingress", tls: NebulaTLSContext? = nil, identifier: UUID = UUID()) {
        self.identifier = identifier
        self.name = name
        self.tls = tls
    }
}

// MARK: - Dispatcher registration

extension StandardIngress {

    public func register(on dispatcher: NMTDispatcher) {
        dispatcher.register(RegisterMatter.self) { [unowned self] matter, _ in
            try await self.handleRegister(matter)
        }
        dispatcher.register(FindMatter.self) { [unowned self] matter, _ in
            try await self.handleFind(matter)
        }
        dispatcher.register(UnregisterMatter.self) { [unowned self] matter, _ in
            try await self.handleUnregister(matter)
        }
        dispatcher.register(EnqueueMatter.self) { [unowned self] matter, _ in
            try await self.handleEnqueue(matter)
        }
        dispatcher.register(FindGalaxyMatter.self) { [unowned self] matter, _ in
            await self.handleFindGalaxy(matter)
        }
        dispatcher.register(CloneMatter.self) { [unowned self] _, _ in
            await self.cloneReply()
        }
    }
}

// MARK: - Handlers

extension StandardIngress {

    private func handleRegister(_ matter: RegisterMatter) throws -> RegisterReplyMatter {
        let address = try SocketAddress.makeAddressResolvingHost(matter.host, port: matter.port)
        galaxyRegistry[matter.namespace] = address
        return RegisterReplyMatter(status: "ok")
    }

    private func handleFind(_ matter: FindMatter) async throws -> FindReplyMatter {
        let galaxyName = String(matter.namespace.split(separator: ".").first ?? Substring(matter.namespace))
        guard let galaxyAddress = galaxyRegistry[galaxyName] else { return FindReplyMatter() }
        let client = try await galaxyClient(for: galaxyName, at: galaxyAddress)
        let reply = try await client.base.request(.find(namespace: matter.namespace))
        return try reply.decode(FindReplyMatter.self)
    }

    private func handleUnregister(_ matter: UnregisterMatter) async throws -> UnregisterReplyMatter {
        let galaxyName = String(matter.namespace.split(separator: ".").first ?? Substring(matter.namespace))
        guard let galaxyAddress = galaxyRegistry[galaxyName] else { return UnregisterReplyMatter() }
        let client = try await galaxyClient(for: galaxyName, at: galaxyAddress)
        let reply = try await client.base.request(.unregister(namespace: matter.namespace, host: matter.host, port: matter.port))
        return try reply.decode(UnregisterReplyMatter.self)
    }

    private func handleEnqueue(_ matter: EnqueueMatter) async throws -> RegisterReplyMatter {
        let galaxyName = String(matter.namespace.split(separator: ".").first ?? Substring(matter.namespace))
        guard let galaxyAddress = galaxyRegistry[galaxyName] else {
            return RegisterReplyMatter(status: "no-galaxy")
        }
        let client = try await galaxyClient(for: galaxyName, at: galaxyAddress)
        let reply = try await client.base.request(.enqueue(namespace: matter.namespace, service: matter.service, method: matter.method, arguments: matter.arguments))
        return try reply.decode(RegisterReplyMatter.self)
    }

    private func handleFindGalaxy(_ matter: FindGalaxyMatter) -> FindGalaxyReplyMatter {
        let galaxyName = String(matter.topic.split(separator: ".").first ?? Substring(matter.topic))
        guard let address = galaxyRegistry[galaxyName] else { return FindGalaxyReplyMatter() }
        return FindGalaxyReplyMatter(galaxyHost: address.ipAddress, galaxyPort: address.port)
    }

    private func cloneReply() -> CloneReplyMatter {
        CloneReplyMatter(identifier: identifier.uuidString, name: name, category: 0)
    }
}

// MARK: - Galaxy Client Cache

extension StandardIngress {

    private func galaxyClient(for name: String, at address: SocketAddress) async throws -> GalaxyClient {
        if let existing = galaxyClients[name], existing.address == address { return existing }
        let client = try await GalaxyClient.connect(to: address, tls: tls)
        galaxyClients[name] = client
        return client
    }
}
