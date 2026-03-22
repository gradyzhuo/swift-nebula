//
//  Envelope.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation

// NBLA
public let NebulaEnvelopeMagic: [UInt8] = [0x4E, 0x42, 0x4C, 0x41]

/// Nebula wire protocol envelope.
///
/// Header layout (27 bytes, fixed):
/// ```
/// Magic    [0..3]   = "NBLA"  (4 bytes)
/// Version  [4]      = UInt8   (1 byte)
/// Type     [5]      = UInt8   (1 byte)
/// Flags    [6]      = UInt8   (1 byte)
/// MsgID    [7..22]  = UUID    (16 bytes)
/// Length   [23..26] = UInt32  (4 bytes, big-endian)
/// Body     [27..]   = MessagePack encoded payload (variable)
/// ```
public struct Envelope: Sendable {
    public static let headerSize = 27

    public let version: UInt8
    public let type: MessageType
    public let flags: UInt8
    public let messageID: UUID
    public let body: Data

    public init(type: MessageType, flags: UInt8 = 0, messageID: UUID = UUID(), body: Data) {
        self.version = 1
        self.type = type
        self.flags = flags
        self.messageID = messageID
        self.body = body
    }
}

// MARK: - Serialization

extension Envelope {

    public func serialized() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Self.headerSize + body.count)
        // Magic
        bytes.append(contentsOf: NebulaEnvelopeMagic)
        // Version
        bytes.append(version)
        // Type
        bytes.append(type.rawValue)
        // Flags
        bytes.append(flags)
        // MsgID
        bytes.append(contentsOf: messageID.bytes)
        // Length (big-endian)
        bytes.append(contentsOf: UInt32(body.count).bytes())
        // Body
        bytes.append(contentsOf: body)
        return bytes
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= Envelope.headerSize else {
            throw NebulaError.invalidEnvelope("Too short: \(bytes.count) bytes")
        }

        let magic = Array(bytes[0..<4])
        guard magic == NebulaEnvelopeMagic else {
            throw NebulaError.invalidEnvelope("Invalid magic bytes")
        }

        let version = bytes[4]

        guard let type = MessageType(rawValue: bytes[5]) else {
            throw NebulaError.invalidEnvelope("Unknown message type: \(bytes[5])")
        }

        let flags = bytes[6]

        let messageID = try UUID(bytes: Array(bytes[7..<23]))

        let length = Int(UInt32(bytes: Array(bytes[23..<27])))

        guard bytes.count >= Envelope.headerSize + length else {
            throw NebulaError.invalidEnvelope("Body length mismatch")
        }

        let body = Data(bytes[Envelope.headerSize ..< Envelope.headerSize + length])

        self.version = version
        self.type = type
        self.flags = flags
        self.messageID = messageID
        self.body = body
    }
}
