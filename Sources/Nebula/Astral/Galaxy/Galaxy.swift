//
//  Galaxy.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public protocol Galaxy: Astral {
    var registry: any ServiceRegistry { get }

    /// Register a Stellar endpoint under a namespace.
    /// Galaxy automatically creates and manages a LoadBalanceAmas for the namespace.
    func register(namespace: String, stellarEndpoint: SocketAddress) async throws
}

extension Galaxy {
    public static var category: AstralCategory { .galaxy }
}
