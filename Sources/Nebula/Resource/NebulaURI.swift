//
//  NebulaURI.swift
//
//
//  Created by Grady Zhuo on 2026/3/23.
//

import Foundation

/// Represents an `nmtp://` URI used to address a service endpoint via Ingress.
///
/// Namespace format follows forward order (discovery path): `{galaxy}.{amas}.{stellar}`
/// — broadest first, most specific last. Reading left to right matches the routing path.
///
/// Single format — host:port is always the Ingress address:
///
/// ```
/// nmtp://localhost:22400/production.ml.embedding/w2v/wordVector?key=value
///        └─────────────┘ └──────────────────────┘ └──┘ └────────┘
///        Ingress address  namespace (galaxy.amas.stellar) svc  method
/// ```
///
/// Query string arguments support JSON strings, numbers, booleans, and arrays.
public struct NebulaURI: Sendable {
    public static let scheme = "nmtp"

    public let user: String?
    public let password: String?

    /// Ingress host address (e.g. `localhost`, `192.168.1.1`, `::1`).
    public let ingressHost: String
    /// Ingress port (e.g. `22400`).
    public let ingressPort: Int

    /// The service namespace in forward order (e.g. `production.ml.embedding`).
    public let namespace: String
    /// Service name (e.g. `w2v`).
    public let service: String?
    /// Method name (e.g. `wordVector`).
    public let method: String?
    /// Arguments from query string.
    public let arguments: [Argument]

    /// Galaxy name — first dot-separated segment of namespace.
    /// e.g. `"production"` from `"production.ml.embedding"`.
    public var galaxyName: String {
        String(namespace.split(separator: ".").first ?? Substring(namespace))
    }

    public init(_ string: String) throws {
        guard let components = URLComponents(string: string),
              components.scheme == Self.scheme else {
            throw NebulaError.invalidURI("URI must use nmtp:// scheme: \(string)")
        }

        guard let host = components.host, !host.isEmpty else {
            throw NebulaError.invalidURI("Missing Ingress host in URI: \(string)")
        }

        guard let port = components.port else {
            throw NebulaError.invalidURI("Missing Ingress port in URI: \(string)")
        }

        user     = components.user
        password = components.password

        ingressHost = host
        ingressPort = port

        let pathParts = components.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)

        guard !pathParts.isEmpty else {
            throw NebulaError.invalidURI("Missing namespace in URI: \(string)")
        }

        namespace = pathParts[0]
        service   = pathParts.count > 1 ? pathParts[1] : nil
        method    = pathParts.count > 2 ? pathParts[2] : nil

        arguments = try (components.queryItems ?? []).map { item in
            try NebulaURI.parseArgument(key: item.name, rawValue: item.value ?? "")
        }
    }
}

// MARK: - Argument Parsing

extension NebulaURI {

    private static func parseArgument(key: String, rawValue: String) throws -> Argument {
        if let data = rawValue.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) {
            return try Argument.wrap(key: key, value: ArgumentValue(jsonObject))
        }
        return try Argument.wrap(key: key, value: rawValue)
    }
}
