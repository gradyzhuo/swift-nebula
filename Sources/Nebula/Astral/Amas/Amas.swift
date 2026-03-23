//
//  Amas.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation
import NIO

public protocol Amas: Astral {
    /// Namespace prefix this Amas manages, e.g. "embedding.ml"
    var namespace: String { get }
}

extension Amas {
    public static var category: AstralCategory { .amas }
}
