//
//  NMTServerTarget.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

/// A type that can serve as the handler for an NMTServer.
///
/// A **target** serves two purposes:
/// 1. Specifies the node role (Galaxy / Amas / Stellar)
/// 2. Handles incoming Matter messages for that role
///
/// `channel` is the connection the message arrived on.
/// Most handlers ignore it; `BrokerAmas` uses it to store subscriber channels for push.
public protocol NMTServerTarget: Sendable {
    func handle(envelope: Matter, channel: Channel) async throws -> Matter?
}
