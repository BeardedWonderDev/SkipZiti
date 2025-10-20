import XCTest
@testable import SkipZiti

final class SkipZitiClientTests: XCTestCase {
    func testBootstrapWithUnsupportedBridge() async {
        let configuration = SkipZitiConfiguration(controllerURL: URL(string: "wss://controller.example")!)
        let bridge = UnsupportedBridge()
        do {
            _ = try await SkipZiti.bootstrap(configuration: configuration, bridge: bridge)
            XCTFail("Expected unsupported platform failure")
        } catch let error as SkipZitiError {
            guard case .unsupportedPlatform = error else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private struct UnsupportedBridge: SkipZitiPlatformBridge {
    func start(configuration: SkipZitiConfiguration, emit: @escaping (SkipZitiClientEvent) -> Void) async throws {
        throw SkipZitiError.unsupportedPlatform(reason: "test stub")
    }

    func shutdown() async {}

    func enroll(jwt: Data, alias: String) async throws -> SkipZitiIdentityRecord {
        throw SkipZitiError.unsupportedPlatform(reason: "test stub")
    }

    func revoke(alias: String) async throws {
        throw SkipZitiError.unsupportedPlatform(reason: "test stub")
    }

    func cachedIdentities() async throws -> [SkipZitiIdentityRecord] { [] }
}
