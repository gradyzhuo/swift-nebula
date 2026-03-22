import Foundation
import Nebula
import NIO

// Direct connection to Stellar (bypassing Amas, for testing)
let stellarAddress = try SocketAddress(ipAddress: "::1", port: 7000)
let client = try await NMTClient.connect(to: stellarAddress)

let body = CallBody(
    namespace: "production.ml.embedding",
    service: "w2v",
    method: "wordVector",
    arguments: [try Argument.wrap(key: "words", value: ["hello", "world"])]
        .toEncoded()
        .map { EncodedArgument(key: $0.key, value: $0.value) }
)
let envelope = try Matter.make(type: .call, body: body)
let reply = try await client.request(envelope: envelope)
let replyBody = try reply.decodeBody(CallReplyBody.self)

print("Result:", replyBody.result as Any)
