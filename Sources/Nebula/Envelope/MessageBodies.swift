//
//  MessageBodies.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation

// MARK: - Clone

public struct CloneBody: Codable, Sendable {}

public struct CloneReplyBody: Codable, Sendable {
    public var identifier: String
    public var name: String
    public var category: UInt8

    public init(identifier: String, name: String, category: UInt8) {
        self.identifier = identifier
        self.name = name
        self.category = category
    }
}

// MARK: - Register

public struct RegisterBody: Codable, Sendable {
    /// Fully qualified namespace, e.g. "production.ml.embedding"
    public var namespace: String
    public var host: String
    public var port: Int
    public var identifier: String

    public init(namespace: String, host: String, port: Int, identifier: String) {
        self.namespace = namespace
        self.host = host
        self.port = port
        self.identifier = identifier
    }
}

public struct RegisterReplyBody: Codable, Sendable {
    public var status: String

    public init(status: String) {
        self.status = status
    }
}

// MARK: - Find

public struct FindBody: Codable, Sendable {
    public var namespace: String

    public init(namespace: String) {
        self.namespace = namespace
    }
}

public struct FindReplyBody: Codable, Sendable {
    /// nil means not found
    public var address: String?

    public init(address: String?) {
        self.address = address
    }
}

// MARK: - Call

public struct CallBody: Codable, Sendable {
    public var namespace: String
    public var service: String
    public var method: String
    public var arguments: [EncodedArgument]

    public init(namespace: String, service: String, method: String, arguments: [EncodedArgument]) {
        self.namespace = namespace
        self.service = service
        self.method = method
        self.arguments = arguments
    }
}

public struct EncodedArgument: Codable, Sendable {
    public var key: String
    public var value: Data

    public init(key: String, value: Data) {
        self.key = key
        self.value = value
    }
}

public struct CallReplyBody: Codable, Sendable {
    public var result: Data?
    public var error: String?

    public init(result: Data? = nil, error: String? = nil) {
        self.result = result
        self.error = error
    }
}
