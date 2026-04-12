// Sources/Nebula/NMT/Matter+Nebula.swift

import Foundation
import NMTP
import MessagePacker

// MARK: - MatterBehavior factory

extension Matter {

    /// Create a Matter from a `MatterBehavior`-conforming value.
    /// The frame `type` and payload `typeID` are derived from the action's static metadata.
    /// The body is MessagePack-encoded.
    public static func make<A: MatterBehavior>(_ action: A) throws -> Matter {
        let body = try MessagePackEncoder().encode(action)
        return Matter.make(type: A.type, typeID: A.typeID, body: body)
    }

    /// MessagePack-decode this Matter's payload body as type `T`.
    public func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let payload = try decodePayload()
        return try MessagePackDecoder().decode(type, from: payload.body)
    }

    /// Create a reply Matter matching this Matter's matterID, with a MessagePack-encoded body.
    public func makeReply<R: Encodable>(body: R) throws -> Matter {
        let encoded = try MessagePackEncoder().encode(body)
        let payload = MatterPayload(typeID: 0, body: encoded)
        return makeReply(payload: payload.encoded)
    }
}
