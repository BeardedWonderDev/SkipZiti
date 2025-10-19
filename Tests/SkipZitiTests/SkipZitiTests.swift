import XCTest
@testable import SkipZiti

final class SkipZitiTests: XCTestCase {
    func testBootstrapEmitsReadyEvent() async throws {
        let store = InMemoryIdentityStore()
        let controller = MockController()
        let client = try await SkipZiti.bootstrap(
            controllerURL: URL(string: "wss://controller.example")!,
            identityStore: store,
            controller: controller
        )

        var iterator = client.events.makeAsyncIterator()
        let first = await iterator.next()
        guard case .starting? = first else {
            XCTFail("Expected starting event, got \(String(describing: first))")
            return
        }

        let second = await iterator.next()
        guard case .ready(let services)? = second else {
            XCTFail("Expected ready event, got \(String(describing: second))")
            return
        }
        XCTAssertTrue(services.isEmpty)

        await client.shutdown()
    }
}

private struct MockController: SkipZitiControllerClient {
    func enroll(csr: Data, alias: String) async throws -> SkipZitiIdentityPayload {
        SkipZitiIdentityPayload(
            certificate: Data("cert-\(alias)".utf8),
            privateKey: Data("key-\(alias)".utf8),
            controller: URL(string: "wss://controller.example")!,
            alias: alias
        )
    }

    func revoke(alias: String) async throws {}
}
