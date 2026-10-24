//
//  BPHelperSecurityTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPHelperSecurityTests: XCTestCase, @unchecked Sendable {

    // MARK: - identifiers

    func testMachServiceNameIsNamespacedUnderTheApp() {
        XCTAssertEqual(BPHelperMachServiceName, "com.scottdensmore.Cakebrew.Helper")
    }

    func testHelperIdentifierMatchesTheMachServiceName() {
        XCTAssertEqual(BPHelperIdentifier, BPHelperMachServiceName)
    }

    // MARK: - client requirement (who may drive the helper)

    func testClientRequirementPinsTheAppIdentifier() {
        let req = BPHelperSecurity.clientCodeSigningRequirement()
        XCTAssertTrue(
            req.contains("identifier \"com.scottdensmore.Cakebrew\""),
            "only the Cakebrew app may drive the helper: \(req)"
        )
    }

    func testClientRequirementPinsTheTeamAndAppleAnchor() {
        let req = BPHelperSecurity.clientCodeSigningRequirement()
        XCTAssertTrue(req.contains("anchor apple generic"), "\(req)")
        XCTAssertTrue(req.contains("certificate leaf[subject.OU] = \"27ZDER873F\""), "\(req)")
    }

    func testClientRequirementIsNotTriviallyPermissive() {
        let req = BPHelperSecurity.clientCodeSigningRequirement()
        XCTAssertFalse(req.contains(" or "), "no alternation that could widen the requirement: \(req)")
        XCTAssertGreaterThan(req.count, 40, "requirement should be a real constraint: \(req)")
    }

    // MARK: - helper requirement (who the app will accept as the helper)

    func testHelperRequirementPinsTheHelperIdentifierAndTeam() {
        let req = BPHelperSecurity.helperCodeSigningRequirement()
        XCTAssertTrue(req.contains("identifier \"com.scottdensmore.Cakebrew.Helper\""), "\(req)")
        XCTAssertTrue(req.contains("anchor apple generic"), "\(req)")
        XCTAssertTrue(req.contains("certificate leaf[subject.OU] = \"27ZDER873F\""), "\(req)")
    }

    func testTheTwoRequirementsAreNotInterchangeable() {
        XCTAssertNotEqual(
            BPHelperSecurity.clientCodeSigningRequirement(),
            BPHelperSecurity.helperCodeSigningRequirement(),
            "each side must pin the other's identifier, not its own"
        )
    }
}
