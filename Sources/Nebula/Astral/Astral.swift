//
//  Astral.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public enum AstralCategory: UInt8, Sendable {
    case planet    = 1
    case stellar   = 2
    case amas      = 4
    case galaxy    = 8

    public var name: String {
        switch self {
        case .planet:  return "Planet"
        case .stellar: return "Stellar"
        case .amas:    return "Amas"
        case .galaxy:  return "Galaxy"
        }
    }
}

public protocol Astral: Sendable {
    static var category: AstralCategory { get }
    var identifier: UUID { get }
    var name: String { get }
    var namespace: String { get }
}

public protocol ServerAstral: Astral, NMTServerTarget {}

extension Astral {
    public var namespace: String { name }

    /// Validates that a name does not contain `.` which is reserved as the namespace separator.
    public static func validateName(_ name: String) throws {
        guard !name.contains(".") else {
            throw NebulaError.fail(message: "Astral name must not contain '.': \"\(name)\"")
        }
    }
}
