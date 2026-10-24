//
//  BPHelperRegistrationTests.swift
//  CakebrewTests
//

import Foundation
import ServiceManagement
import XCTest

final class BPHelperRegistrationTests: XCTestCase, @unchecked Sendable {

    // MARK: - transport gating

    func testDirectTransportNeedsNoHelperAtAll() {
        let state = BPHelperRegistration.state(forTransport: .direct, serviceStatus: .notRegistered)
        XCTAssertEqual(state, .notRequired)
        XCTAssertTrue(
            BPHelperRegistration.stateAllowsBrewOperations(state),
            "direct transport must never be blocked by helper state"
        )
    }

    // MARK: - status mapping (helper transport)

    func testEnabledServiceIsReady() {
        let state = BPHelperRegistration.state(forTransport: .helper, serviceStatus: .enabled)
        XCTAssertEqual(state, .ready)
        XCTAssertTrue(BPHelperRegistration.stateAllowsBrewOperations(state))
    }

    func testRequiresApprovalIsSurfacedAndBlocks() {
        let state = BPHelperRegistration.state(forTransport: .helper, serviceStatus: .requiresApproval)
        XCTAssertEqual(state, .needsApproval)
        XCTAssertFalse(
            BPHelperRegistration.stateAllowsBrewOperations(state),
            "brew cannot run until the user approves the background item"
        )
        XCTAssertTrue(
            BPHelperRegistration.stateOffersLoginItemsShortcut(state),
            "this is the one state where pointing at Login Items helps"
        )
    }

    func testNotRegisteredBlocksAndDoesNotOfferLoginItems() {
        let state = BPHelperRegistration.state(forTransport: .helper, serviceStatus: .notRegistered)
        XCTAssertEqual(state, .notRegistered)
        XCTAssertFalse(BPHelperRegistration.stateAllowsBrewOperations(state))
        XCTAssertFalse(
            BPHelperRegistration.stateOffersLoginItemsShortcut(state),
            "nothing to approve yet — the app should register first"
        )
    }

    func testNotFoundIsUnavailable() {
        let state = BPHelperRegistration.state(forTransport: .helper, serviceStatus: .notFound)
        XCTAssertEqual(state, .unavailable)
        XCTAssertFalse(BPHelperRegistration.stateAllowsBrewOperations(state))
    }

    func testUnknownFutureStatusFailsClosed() {
        let unknownStatus = unsafeBitCast(99 as Int, to: SMAppService.Status.self)
        let state = BPHelperRegistration.state(forTransport: .helper, serviceStatus: unknownStatus)
        XCTAssertEqual(state, .unavailable, "an unrecognised status must not read as ready")
        XCTAssertFalse(BPHelperRegistration.stateAllowsBrewOperations(state))
    }

    // MARK: - user-facing description

    func testEveryStateHasANonEmptyDescription() {
        let states: [BPHelperState] = [.notRequired, .ready, .needsApproval, .notRegistered, .unavailable]
        for state in states {
            let text = BPHelperRegistration.localizedDescription(forState: state)
            XCTAssertFalse(text.isEmpty, "state \(state.rawValue) needs something to show the user")
        }
    }

    // MARK: - identifiers

    func testPlistNameMatchesTheRegisteredIdentifier() {
        XCTAssertEqual(BPHelperRegistration.agentPlistName(), "com.scottdensmore.Cakebrew.Helper.plist")
    }
}
