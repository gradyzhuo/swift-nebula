//
//  Amas.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

/// Internal load balancer managed by Galaxy.
/// Amas is not exposed as a standalone TCP server.
public protocol Amas: Sendable {
    var identifier: UUID { get }
    var name: String { get }
    var namespace: String { get }
}
