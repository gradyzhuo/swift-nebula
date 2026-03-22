//
//  Envelope+Coding.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import MessagePacker

// MARK: - Body Encoding

extension Envelope {

    public static func make<T: Encodable>(
        type: MessageType,
        body: T,
        messageID: UUID = UUID(),
        flags: UInt8 = 0
    ) throws -> Envelope {
        let data = try MessagePackEncoder().encode(body)
        return Envelope(type: type, flags: flags, messageID: messageID, body: data)
    }

    /// Create a reply envelope that matches the request's messageID.
    public func reply<T: Encodable>(body: T) throws -> Envelope {
        let data = try MessagePackEncoder().encode(body)
        return Envelope(type: .reply, messageID: messageID, body: data)
    }
}

// MARK: - Body Decoding

extension Envelope {

    public func decodeBody<T: Decodable>(_ type: T.Type) throws -> T {
        return try MessagePackDecoder().decode(type, from: body)
    }
}
