//
//  EnvelopeDecoder.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

final class EnvelopeDecoder: ByteToMessageDecoder {
    typealias InboundOut = Envelope

    func decode(context: ChannelHandlerContext, buffer: inout ByteBuffer) throws -> DecodingState {
        guard buffer.readableBytes >= Envelope.headerSize else {
            return .needMoreData
        }

        guard let bodyLength = buffer.getInteger(
            at: buffer.readerIndex + 23,
            endianness: .big,
            as: UInt32.self
        ) else {
            return .needMoreData
        }

        let totalLength = Envelope.headerSize + Int(bodyLength)
        guard buffer.readableBytes >= totalLength else {
            return .needMoreData
        }

        guard let frameBytes = buffer.readBytes(length: totalLength) else {
            return .needMoreData
        }

        let envelope = try Envelope(bytes: frameBytes)
        context.fireChannelRead(wrapInboundOut(envelope))
        return .continue
    }

    func decodeLast(context: ChannelHandlerContext, buffer: inout ByteBuffer, seenEOF: Bool) throws -> DecodingState {
        return .needMoreData
    }
}
