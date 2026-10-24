//
//  BPBrewTransportTests.swift
//  CakebrewTests
//
//  The transport seam decides whether brew runs in-process (today) or in the
//  non-sandboxed helper. Getting the default wrong would either break the
//  shipping app or silently bypass the sandbox, so it is pinned here.
//

import Foundation
import XCTest

final class BPBrewTransportTests: XCTestCase, @unchecked Sendable {

    // MARK: - transport selection

    func testUnsandboxedBuildsRunBrewInProcess() {
        XCTAssertEqual(
            BPHomebrewInterface.defaultTransport(whenSandboxed: false),
            .direct,
            "the shipping Developer ID build must keep running brew directly"
        )
    }

    func testSandboxedBuildsRouteThroughTheHelper() {
        XCTAssertEqual(
            BPHomebrewInterface.defaultTransport(whenSandboxed: true),
            .helper,
            "a sandboxed app cannot exec brew itself"
        )
    }

    func testTestRunIsNotSandboxedSoTheDefaultIsDirect() {
        XCTAssertFalse(BPHomebrewInterface.isRunningSandboxed())
        XCTAssertEqual(BPHomebrewInterface.sharedInterface().brewTransport, .direct)
    }

    // MARK: - reply/stream reconciliation

    func testUndeliveredTailIsNilWhenEverythingStreamed() {
        XCTAssertNil(BPHelperClient.undeliveredTail(ofOutput: "abcdef", deliveredLength: 6))
    }

    func testUndeliveredTailReturnsWhatTheSinkMissed() {
        XCTAssertEqual(
            BPHelperClient.undeliveredTail(ofOutput: "abcdef", deliveredLength: 4),
            "ef",
            "the reply can outrun the last chunks; the tail must still reach the caller"
        )
    }

    func testUndeliveredTailToleratesOverDelivery() {
        XCTAssertNil(BPHelperClient.undeliveredTail(ofOutput: "abc", deliveredLength: 99))
        XCTAssertNil(BPHelperClient.undeliveredTail(ofOutput: nil, deliveredLength: 0))
    }
}
