@testable import SkipZiti
import XCTest

final class ServiceDescriptorTests: XCTestCase {
    func testServiceDescriptorFromSummaryMapsPermissions() {
        let intercept = SkipZitiServiceSummary.Intercept(
            addresses: ["example.com"],
            protocols: ["tcp"],
            portRanges: [SkipZitiPortRange(lowerBound: 80, upperBound: 80)],
            sourceIP: "1.2.3.4",
            dialIdentity: "demo",
            connectTimeoutSeconds: 15
        )

        let postureQuery = SkipZitiPostureQuery(
            id: "pq-1",
            type: "os",
            isPassing: true,
            timeout: 10,
            timeoutRemaining: 5
        )

        let postureSet = SkipZitiPostureCheckSet(
            policyId: "policy-1",
            policyType: "bind",
            isPassing: true,
            queries: [postureQuery]
        )

        let summary = SkipZitiServiceSummary(
            name: "Demo Service",
            identifier: "svc-1",
            isEncrypted: true,
            permFlags: 0x03,
            intercepts: [intercept],
            postureChecks: [postureSet],
            attributes: ["rawService": "{\"name\":\"Demo\"}"]
        )

        let descriptor = SkipZitiServiceDescriptor.fromSummary(summary)
        XCTAssertEqual(descriptor.name, "Demo Service")
        XCTAssertEqual(descriptor.identifier, "svc-1")
        XCTAssertTrue(descriptor.isEncrypted)
        XCTAssertTrue(descriptor.permissions.canDial)
        XCTAssertTrue(descriptor.permissions.canBind)
        XCTAssertEqual(descriptor.intercepts.count, 1)
        XCTAssertEqual(descriptor.intercepts.first?.addresses, ["example.com"])
        XCTAssertEqual(descriptor.postureChecks.first?.queries.first?.id, "pq-1")
        XCTAssertEqual(descriptor.attributes.value(forKey: "rawService"), "{\"name\":\"Demo\"}")
    }

    func testServiceUpdateEquatable() {
        let descriptor = SkipZitiServiceDescriptor(
            name: "Demo",
            identifier: "svc",
            isEncrypted: false,
            permissions: SkipZitiServicePermissions(canDial: true, canBind: false),
            intercepts: [],
            postureChecks: [],
            attributes: [:]
        )

        let lhs = SkipZitiServiceUpdate(
            identityAlias: "alias",
            changeSource: .delta,
            added: [descriptor],
            removed: [],
            changed: []
        )
        let rhs = lhs
        XCTAssertEqual(lhs, rhs)
    }

    func testPostureQueryEventEquatable() {
        let event = SkipZitiPostureQueryEvent(
            identityAlias: "alias",
            queryType: .operatingSystem,
            resolution: .satisfied("macOS 14")
        )

        XCTAssertEqual(event, event)
        let unsupported = SkipZitiPostureQueryEvent(
            identityAlias: "alias",
            queryType: .operatingSystem,
            resolution: .unsupported
        )
        XCTAssertNotEqual(event, unsupported)
    }

    func testReportedErrorEquatable() {
        let error = SkipZitiReportedError(stage: .runtime, message: "failure", details: "timeout", recoverable: false)
        XCTAssertEqual(error, error)
        let other = SkipZitiReportedError(stage: .runtime, message: "failure", details: "timeout", recoverable: true)
        XCTAssertNotEqual(error, other)
    }
}
