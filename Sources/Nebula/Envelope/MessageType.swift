//
//  MessageType.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation

public enum MessageType: UInt8, Sendable {
    case clone      = 0x01
    case register   = 0x02
    case find       = 0x03
    case call       = 0x04
    case reply      = 0x05
    case activate   = 0x06
    case heartbeat  = 0x07
}
