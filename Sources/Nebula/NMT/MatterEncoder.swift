//
//  MatterEncoder.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

final class MatterEncoder: MessageToByteEncoder {
    typealias OutboundIn = Matter

    func encode(data: Matter, out: inout ByteBuffer) throws {
        out.writeBytes(data.serialized())
    }
}
