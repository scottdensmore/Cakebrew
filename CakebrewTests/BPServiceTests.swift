//
//  BPServiceTests.swift
//  CakebrewTests
//
//  Tests for BPService: parsing `brew services list --json` output into
//  service objects, defensively (brew's JSON has nulls, and output may not
//  be JSON at all when brew errors).
//

import XCTest

final class BPServiceTests: XCTestCase, @unchecked Sendable {

    func testParsesEmptyArray() {
        // The common case on machines with no services installed.
        XCTAssertEqual(BPService.services(fromJSONString: "[]"), [])
    }

    func testParsesFullServiceEntry() {
        let json = "[{\"name\":\"postgresql@14\",\"service_name\":\"homebrew.mxcl.postgresql@14\","
            + "\"running\":true,\"loaded\":true,\"schedulable\":false,\"pid\":123,"
            + "\"exit_code\":null,\"user\":\"scott\",\"status\":\"started\","
            + "\"file\":\"~/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist\",\"registered\":true}]"

        let services = BPService.services(fromJSONString: json)

        XCTAssertEqual(services.count, 1)
        let service = services.first
        XCTAssertEqual(service?.name, "postgresql@14")
        XCTAssertEqual(service?.status, .started)
        XCTAssertEqual(service?.statusString, "started")
        XCTAssertEqual(service?.user, "scott")
        XCTAssertEqual(service?.pid, NSNumber(value: 123))
    }

    func testParsesNullUserAndPid() {
        // Stopped services report user and pid as JSON null.
        let json = "[{\"name\":\"redis\",\"running\":false,\"pid\":null,\"user\":null,\"status\":\"none\"}]"

        let services = BPService.services(fromJSONString: json)

        XCTAssertEqual(services.count, 1)
        let service = services.first
        XCTAssertEqual(service?.name, "redis")
        XCTAssertEqual(service?.status, BPServiceStatus.none)
        XCTAssertNil(service?.user)
        XCTAssertNil(service?.pid)
    }

    func testStatusMapping() {
        let cases: [String: BPServiceStatus] = [
            "started": .started,
            "stopped": .stopped,
            "none": .none,
            "error": .error,
            "scheduled": .scheduled,
            "banana": .unknown // unrecognized -> unknown
        ]

        for (raw, expected) in cases {
            let json = "[{\"name\":\"svc\",\"status\":\"\(raw)\"}]"
            let service = BPService.services(fromJSONString: json).first
            XCTAssertEqual(service?.status, expected, "status '\(raw)' should map correctly")
        }
    }

    func testNonJSONOutputYieldsEmptyList() {
        // brew can print an error message instead of JSON; never crash on it.
        XCTAssertEqual(BPService.services(fromJSONString: "Error: some brew failure"), [])
        XCTAssertEqual(BPService.services(fromJSONString: ""), [])
    }

    func testNonArrayJSONYieldsEmptyList() {
        XCTAssertEqual(BPService.services(fromJSONString: "{\"name\":\"redis\"}"), [])
    }

    func testEntriesWithoutANameAreSkipped() {
        let json = "[{\"status\":\"started\"},{\"name\":\"redis\",\"status\":\"none\"}]"

        let services = BPService.services(fromJSONString: json)

        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services.first?.name, "redis")
    }
}
