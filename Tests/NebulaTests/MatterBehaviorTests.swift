// Tests/NebulaTests/MatterBehaviorTests.swift

import Testing
import Foundation
import NMTP
import MessagePacker
@testable import Nebula

// A minimal conforming type for testing the protocol contract.
private struct TestMatter: MatterBehavior {
    static let typeID: UInt16 = 0xFFFE
    static let type: NMTP.MatterBehavior = .query
    let value: String
}

@Suite("MatterBehavior protocol")
struct MatterBehaviorProtocolTests {

    @Test("Conforming type exposes typeID and type")
    func conformingTypeExposesMetadata() {
        #expect(TestMatter.typeID == 0xFFFE)
        #expect(TestMatter.type == NMTP.MatterBehavior.query)
    }

    @Test("Conforming type is Codable")
    func conformingTypeIsCodable() throws {
        let original = TestMatter(value: "hello")
        let data = try MessagePackEncoder().encode(original)
        let decoded = try MessagePackDecoder().decode(TestMatter.self, from: data)
        #expect(decoded.value == original.value)
    }
}
