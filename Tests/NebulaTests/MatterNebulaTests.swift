// Tests/NebulaTests/MatterNebulaTests.swift

import Testing
import Foundation
import NIO
import NMTP
import MessagePacker
@testable import Nebula

@Suite("Matter+Nebula extensions")
struct MatterNebulaTests {

    @Test("Matter.make encodes MatterBehavior with correct typeID and MatterType")
    func makeFromMatterBehavior() throws {
        let matter = try Matter.make(FindMatter(namespace: "test.echo"))
        let payload = try matter.decodePayload()
        #expect(matter.type == .query)
        #expect(payload.typeID == FindMatter.typeID)
        let decoded = try MessagePackDecoder().decode(FindMatter.self, from: payload.body)
        #expect(decoded.namespace == "test.echo")
    }

    @Test("Matter.decode MessagePack-decodes payload body")
    func decodePayloadBody() throws {
        let original = FindMatter(namespace: "production.ml")
        let matter = try Matter.make(original)
        let decoded = try matter.decode(FindMatter.self)
        #expect(decoded.namespace == "production.ml")
    }

    @Test("Matter.makeReply(body:) encodes reply body with correct matterID")
    func makeNebulaReplyPreservesMatterID() throws {
        let request = try Matter.make(FindMatter(namespace: "test"))
        let replyBody = FindReplyMatter(stellarHost: "127.0.0.1", stellarPort: 1234)
        let reply = try request.makeReply(body: replyBody)
        #expect(reply.matterID == request.matterID)
        #expect(reply.type == .reply)
        let decoded = try reply.decode(FindReplyMatter.self)
        #expect(decoded.stellarHost == "127.0.0.1")
        #expect(decoded.stellarPort == 1234)
    }
}
