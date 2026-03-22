//
//  Matter+Coding.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import MessagePacker

// MARK: - Body Encoding

extension Matter {

    public static func make<T: Encodable>(
        type: MessageType,
        body: T,
        messageID: UUID = UUID(),
        flags: UInt8 = 0
    ) throws -> Matter {
        let data = try MessagePackEncoder().encode(body)
        return Matter(type: type, flags: flags, messageID: messageID, body: data)
    }

    /// Create a reply Matter that matches the request's messageID.
    public func reply<T: Encodable>(body: T) throws -> Matter {
        let data = try MessagePackEncoder().encode(body)
        return Matter(type: .reply, messageID: messageID, body: data)
    }
}

// MARK: - Body Decoding

extension Matter {

    public func decodeBody<T: Decodable>(_ type: T.Type) throws -> T {
        return try MessagePackDecoder().decode(type, from: body)
    }
}
