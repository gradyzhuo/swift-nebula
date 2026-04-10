import Testing
import Foundation
import NIO
import NMTP
@testable import Nebula

@Suite("TypedClient timeout")
struct TypedClientTimeoutTests {

    /// Compile-only test: verifies that connect(defaultTimeout:) exists on all three clients.
    /// The connects are expected to fail at runtime (no server on port 1), so try? is used.
    @Test("connect(defaultTimeout:) parameter exists on all three clients")
    func connectAcceptsDefaultTimeout() async throws {
        let addr = try SocketAddress.makeAddressResolvingHost("127.0.0.1", port: 1)
        _ = try? await GalaxyClient.connect(to: addr, defaultTimeout: .seconds(5))
        _ = try? await IngressClient.connect(to: addr, defaultTimeout: .seconds(5))
        _ = try? await StellarClient.connect(to: addr, defaultTimeout: .seconds(5))
    }
}
