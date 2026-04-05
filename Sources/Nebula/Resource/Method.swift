//
//  Method.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NMTP

public typealias MethodAction = @Sendable (_ args: [Argument]) async throws -> Data?

public protocol Method: Sendable {
    var name: String { get }
    func invoke(arguments: [Argument]) async throws -> Data?
}

public struct ServiceMethod: Method {
    public internal(set) var name: String
    public internal(set) var action: MethodAction

    public init(name: String, action: @escaping MethodAction) {
        self.name = name
        self.action = action
    }

    public func invoke(arguments: [Argument]) async throws -> Data? {
        return try await action(arguments)
    }
}
