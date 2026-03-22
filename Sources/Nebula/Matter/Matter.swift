//
//  Matter.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation

// NBLA
public let NebulaMatterMagic: [UInt8] = [0x4E, 0x42, 0x4C, 0x41]

/// The unit transmitted between nodes in the Nebula protocol (NMT — Nebula Matter Transfer).
///
/// Structurally equivalent to what networking calls an "envelope": a fixed-length header
/// carrying routing metadata, followed by a serialized body. Named `Matter` because in
/// the Nebula metaphor, celestial bodies communicate by transferring matter — not just
/// wrapping messages in envelopes.
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
public struct Matter: Sendable {
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

extension Matter {

    public func serialized() -> [UInt8] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(Self.headerSize + body.count)
        bytes.append(contentsOf: NebulaMatterMagic)
        bytes.append(version)
        bytes.append(type.rawValue)
        bytes.append(flags)
        bytes.append(contentsOf: messageID.bytes)
        bytes.append(contentsOf: UInt32(body.count).bytes())
        bytes.append(contentsOf: body)
        return bytes
    }

    public init(bytes: [UInt8]) throws {
        guard bytes.count >= Matter.headerSize else {
            throw NebulaError.invalidMatter("Too short: \(bytes.count) bytes")
        }

        let magic = Array(bytes[0..<4])
        guard magic == NebulaMatterMagic else {
            throw NebulaError.invalidMatter("Invalid magic bytes")
        }

        let version = bytes[4]

        guard let type = MessageType(rawValue: bytes[5]) else {
            throw NebulaError.invalidMatter("Unknown message type: \(bytes[5])")
        }

        let flags = bytes[6]
        let messageID = try UUID(bytes: Array(bytes[7..<23]))
        let length = Int(UInt32(bytes: Array(bytes[23..<27])))

        guard bytes.count >= Matter.headerSize + length else {
            throw NebulaError.invalidMatter("Body length mismatch")
        }

        let body = Data(bytes[Matter.headerSize ..< Matter.headerSize + length])

        self.version = version
        self.type = type
        self.flags = flags
        self.messageID = messageID
        self.body = body
    }
}
