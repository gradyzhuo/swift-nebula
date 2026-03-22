//
//  Galaxy.swift
//
//
//  Created by Grady Zhuo on 2026/3/22.
//

import Foundation

public protocol Galaxy: Astral {
    var registry: any ServiceRegistry { get }
}

extension Galaxy {
    public static var category: AstralCategory { .galaxy }
}
