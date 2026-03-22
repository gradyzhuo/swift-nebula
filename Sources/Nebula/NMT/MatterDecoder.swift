//
//  MatterDecoder.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

final class MatterDecoder: ByteToMessageDecoder {
    typealias InboundOut = Matter

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes >= Matter.headerSize else {
            return .needMoreData
        }

        guard let bodyLength = buffer.getInteger(
            at: buffer.readerIndex + 23,
            endianness: .big,
            as: UInt32.self
        ) else {
            return .needMoreData
        }

        let totalLength = Matter.headerSize + Int(bodyLength)
        guard buffer.readableBytes >= totalLength else {
            return .needMoreData
        }

        guard let frameBytes = buffer.readBytes(length: totalLength) else {
            return .needMoreData
        }

        let matter = try Matter(bytes: frameBytes)
        context.fireChannelRead(wrapInboundOut(matter))
        return .continue
    }

    func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        return .needMoreData
    }
}
