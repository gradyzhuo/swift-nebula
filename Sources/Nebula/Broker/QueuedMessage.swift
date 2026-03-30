//
//  QueuedMessage.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

import Foundation

public struct QueuedMessage: Codable, Sendable {
    /// Matches `Matter.messageID` — used for deduplication on retry.
    public let id: UUID
    public let namespace: String
    public let service: String
    public let method: String
    public let arguments: [EncodedArgument]
    public let enqueuedAt: Date
    public var retryCount: Int

    public init(
        id: UUID,
        namespace: String,
        service: String,
        method: String,
        arguments: [EncodedArgument],
        enqueuedAt: Date = Date(),
        retryCount: Int = 0
    ) {
        self.id = id
        self.namespace = namespace
        self.service = service
        self.method = method
        self.arguments = arguments
        self.enqueuedAt = enqueuedAt
        self.retryCount = retryCount
    }
}
