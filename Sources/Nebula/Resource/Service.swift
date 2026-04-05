//
//  Service.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NMTP

public class Service: @unchecked Sendable {
    public let name: String
    public let version: String?
    public internal(set) var methods: [String: any Method] = [:]

    public init(name: String, version: String? = nil) {
        self.name = name
        self.version = version
    }

    public convenience init(name: String, version: String? = nil, action: @escaping MethodAction) {
        self.init(name: name, version: version)
        add(method: ServiceMethod(name: name, action: action))
    }
}

// MARK: - Method Management

extension Service {

    @discardableResult
    public func add(method: ServiceMethod) -> Self {
        methods[method.name] = method
        return self
    }

    @discardableResult
    public func add(method name: String, action: @escaping MethodAction) -> Self {
        methods[name] = ServiceMethod(name: name, action: action)
        return self
    }
}

// MARK: - Invocation

extension Service {

    public func perform(method name: String, with arguments: [Argument]) async throws -> Data? {
        guard let method = methods[name] else {
            throw NebulaError.methodNotFound(service: self.name, method: name)
        }
        return try await method.invoke(arguments: arguments)
    }
}
