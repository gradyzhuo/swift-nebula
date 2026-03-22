import Foundation
import Nebula
import NIO

let galaxyAddress = try SocketAddress(ipAddress: "::1", port: 9000)
let galaxyClient = try await NMTClient.connect(to: galaxyAddress)

let findBody = FindBody(namespace: "production.ml")
let envelope = try Envelope.make(type: .find, body: findBody)
let reply = try await galaxyClient.request(envelope: envelope)
let replyBody = try reply.decodeBody(FindReplyBody.self)

print("Found Amas at:", replyBody.address ?? "not found")
