//
//  MatterEncoder.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

final class MatterEncoder: MessageToByteEncoder {
    typealias OutboundIn = Envelope

    func encode(data: Envelope, out: inout ByteBuffer) throws {
        out.writeBytes(data.serialized())
    }
}
