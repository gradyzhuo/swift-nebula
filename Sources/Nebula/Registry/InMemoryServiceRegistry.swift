//
//  InMemoryServiceRegistry.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

/// In-memory implementation of ServiceRegistry. Suitable for single-node or development use.
public actor InMemoryServiceRegistry: ServiceRegistry {
    private var store: [String: SocketAddress] = [:]

    public init() {}

    public func register(namespace: String, address: SocketAddress) async throws {
        store[namespace] = address
    }

    public func unregister(namespace: String) async throws {
        store.removeValue(forKey: namespace)
    }

    public func find(namespace: String) async throws -> SocketAddress? {
        return store[namespace]
    }

    public func all() async -> [String: SocketAddress] {
        return store
    }
}
