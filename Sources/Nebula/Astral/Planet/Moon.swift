//
//  Moon.swift
//
//
//  Created by Grady Zhuo on 2026/3/30.
//

/// A typed proxy over a `RoguePlanet` that enables dynamic method call syntax.
///
/// Obtain via `Nebula.moon(connecting:service:)`. Any member access returns a
/// ``MethodProxy`` for that method name, which is directly callable with
/// keyword arguments.
///
/// ```swift
/// let moon = try await Nebula.moon(connecting: "nmtp://localhost:9000/prod/ml", service: "wordVectors")
///
/// // Raw result (Data?)
/// let data = try await moon.embed(word: "hello")
///
/// // Typed result
/// let result: EmbeddingResult = try await moon.embed.call(as: EmbeddingResult.self, word: "hello")
/// ```
@dynamicMemberLookup
public final class Moon: Satellite {

    public let planet: RoguePlanet

    public init(planet: RoguePlanet) {
        self.planet = planet
    }

    /// Returns a ``MethodProxy`` for the named remote method.
    public subscript(dynamicMember method: String) -> MethodProxy {
        MethodProxy(planet: planet, method: method)
    }
}
