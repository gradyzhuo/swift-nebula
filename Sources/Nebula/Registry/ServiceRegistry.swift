//
//  ServiceRegistry.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public protocol ServiceRegistry: Sendable {
    /// Register a namespace pointing to a socket address.
    func register(namespace: String, address: SocketAddress) async throws

    /// Unregister a namespace.
    func unregister(namespace: String) async throws

    /// Find the address for a given namespace.
    func find(namespace: String) async throws -> SocketAddress?

    /// List all registered namespaces.
    func all() async -> [String: SocketAddress]
}
