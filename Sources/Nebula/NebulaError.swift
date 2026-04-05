import Foundation

public enum NebulaError: Error {
    case fail(message: String)
    case invalidMatter(_ reason: String)
    case invalidURI(_ reason: String)
    case discoveryFailed(name: String)
    case notConnected
    case serviceNotFound(namespace: String)
    case methodNotFound(service: String, method: String)
    case connectionClosed
}
