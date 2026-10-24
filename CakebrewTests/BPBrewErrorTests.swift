//
//  BPBrewErrorTests.swift
//  CakebrewTests
//
//  Building the error from a (status, output) pair is a pure function, so it is
//  tested without running brew at all.
//

import Foundation
import XCTest

final class BPBrewErrorTests: XCTestCase, @unchecked Sendable {

    func testASuccessfulExitProducesNoError() {
        XCTAssertNil(
            BPBrewError.error(forExitStatus: 0, output: "Everything fine\n"),
            "exit 0 is success even when brew printed plenty"
        )
    }

    func testANonZeroExitCarriesTheStatus() {
        let error = BPBrewError.error(forExitStatus: 1, output: "Error: No such keg\n")

        XCTAssertNotNil(error)
        XCTAssertEqual(error?.domain, BPBrewError.errorDomain)
        XCTAssertEqual(error?.code, 2) // BPBrewErrorNonZeroExit
        XCTAssertEqual((error?.userInfo[BPBrewError.exitStatusKey] as? NSNumber)?.intValue, 1)
    }

    func testTheDescriptionQuotesBrewRatherThanInventingWording() {
        let error = BPBrewError.error(forExitStatus: 1, output: "Error: No such keg: /usr/local/Cellar/nope\n")

        XCTAssertTrue(
            error?.localizedDescription.contains("No such keg") == true,
            "got: \(String(describing: error?.localizedDescription))"
        )
    }

    func testOnlyTheTailOfALongTranscriptIsKept() {
        var output = ""
        for i in 0..<500 {
            output.append("line \(i)\n")
        }
        output.append("Error: it broke\n")

        let error = BPBrewError.error(forExitStatus: 1, output: output)

        XCTAssertTrue(error?.localizedDescription.contains("Error: it broke") == true, "the tail must survive")
        XCTAssertLessThan((error?.localizedDescription as NSString?)?.length ?? Int.max, 2000, "the head must not")
        XCTAssertFalse(error?.localizedDescription.contains("line 0\n") == true, "the head must not")
    }

    func testAFailureWithNoOutputStillDescribesItself() {
        let error = BPBrewError.error(forExitStatus: 127, output: "")

        XCTAssertNotNil(error)
        XCTAssertGreaterThan(
            (error?.localizedDescription as NSString?)?.length ?? 0,
            0,
            "an empty message would show a blank alert"
        )
        XCTAssertEqual((error?.userInfo[BPBrewError.exitStatusKey] as? NSNumber)?.intValue, 127)
    }

    func testALaunchFailureIsItsOwnCase() {
        let error = BPBrewError.error(forExitStatus: -1, output: "")

        XCTAssertEqual(error?.code, 1) // BPBrewErrorLaunchFailed
    }
}
