//
//  BPUpgradeArgumentsTests.swift
//  CakebrewTests
//
//  "Upgrade All Outdated" used to recycle the named-upgrade API by passing
//  @[@""]. That was harmless while arguments were joined into the shell
//  command string — the empty string simply vanished. Once arguments moved to
//  positional parameters ("$@") to close the injection hole, the empty string
//  survived as a real argv entry and `brew upgrade ''` started failing with
//  "No such file or directory". These tests pin the argv so the operand list
//  can never carry a blank again.
//

import XCTest

final class BPUpgradeArgumentsTests: XCTestCase, @unchecked Sendable {

    // MARK: - upgrading everything

    func testUpgradingAllFormulaeSendsNoOperands() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingFormulae: nil),
            ["upgrade"],
            "bare `brew upgrade` is how you upgrade everything"
        )
    }

    func testAnEmptySelectionUpgradesEverything() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingFormulae: []),
            ["upgrade"]
        )
    }

    func testTheEmptyStringNeverReachesBrew() {
        // The actual regression: this argv used to be @[@"upgrade", @""].
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingFormulae: [""]),
            ["upgrade"],
            "an empty operand makes brew fail with 'No such file or directory'"
        )
    }

    func testWhitespaceOnlyNamesAreDropped() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingFormulae: [" ", "\n", "\t"]),
            ["upgrade"]
        )
    }

    // MARK: - upgrading a selection

    func testNamedFormulaeArePassedThroughInOrder() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingFormulae: ["wget", "git"]),
            ["upgrade", "wget", "git"]
        )
    }

    func testBlanksAreDroppedFromAMixedSelection() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingFormulae: ["wget", "", "git"]),
            ["upgrade", "wget", "git"],
            "one blank entry must not turn a targeted upgrade into a failed run"
        )
    }

    func testSurroundingWhitespaceIsTrimmedFromNames() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingFormulae: ["  wget  "]),
            ["upgrade", "wget"]
        )
    }

    // MARK: - casks

    func testUpgradingAllCasksKeepsTheCaskFlag() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingCasks: nil),
            ["upgrade", "--cask"]
        )
    }

    func testNamedCasksFollowTheCaskFlag() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingCasks: ["mockchrome", "mockvscode"]),
            ["upgrade", "--cask", "mockchrome", "mockvscode"]
        )
    }

    func testBlankCaskNamesAreDropped() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUpgradingCasks: ["", "mockchrome"]),
            ["upgrade", "--cask", "mockchrome"]
        )
    }

    // MARK: - cask uninstall: zap

    func testUninstallingACaskWithoutZapLeavesTheFlagOff() {
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUninstallingCask: "mockchrome", zap: false),
            ["uninstall", "--cask", "mockchrome"]
        )
    }

    func testZapAsksHomebrewToRunTheCasksZapStanza() {
        // Plain uninstall removes the app bundle and deliberately leaves
        // preferences, application support and launch agents behind.
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUninstallingCask: "mockchrome", zap: true),
            ["uninstall", "--cask", "--zap", "mockchrome"],
            "--zap must precede the token, like every other brew flag here"
        )
    }

    func testABlankCaskTokenIsNeverForwarded() {
        // Same hazard as the upgrade path: a blank operand reaches brew as a real
        // empty argv entry and fails.
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUninstallingCask: "", zap: true),
            ["uninstall", "--cask", "--zap"]
        )
        XCTAssertEqual(
            BPHomebrewInterface.arguments(forUninstallingCask: "  ", zap: false),
            ["uninstall", "--cask"]
        )
    }
}
