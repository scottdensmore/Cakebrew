//
//  BPCatalogRefreshPolicyTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPCatalogRefreshPolicyTests: XCTestCase, @unchecked Sendable {

    // MARK: - commands that change what exists

    func testUpdateRefetchesTheCatalogs() {
        XCTAssertTrue(BPHomebrewInterface.brewCommandChangesCatalogMembership("update"))
    }

    func testTappingAndUntappingRefetchTheCatalogs() {
        XCTAssertTrue(BPHomebrewInterface.brewCommandChangesCatalogMembership("tap"))
        XCTAssertTrue(BPHomebrewInterface.brewCommandChangesCatalogMembership("untap"))
    }

    func testBundleImportRefetchesTheCatalogs() {
        XCTAssertTrue(BPHomebrewInterface.brewCommandChangesCatalogMembership("bundle"))
    }

    // MARK: - commands that only change what is installed

    func testPinningAndUnpinningDoNotRefetchTheCatalogs() {
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("pin"))
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("unpin"))
    }

    func testDoctorDoesNotRefetchTheCatalogs() {
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("doctor"))
    }

    func testInstallUninstallAndUpgradeDoNotRefetchTheCatalogs() {
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("install"))
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("uninstall"))
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("upgrade"))
    }

    func testCleanupAndExportDoNotRefetchTheCatalogs() {
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("cleanup"))
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("export"))
    }

    // MARK: - robustness

    func testUnknownAndEmptyCommandsAreConservativelyTreatedAsCheap() {
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership("services"))
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership(""))
        XCTAssertFalse(BPHomebrewInterface.brewCommandChangesCatalogMembership(nil))
    }

    func testMatchingIsCaseInsensitive() {
        XCTAssertTrue(BPHomebrewInterface.brewCommandChangesCatalogMembership("UPDATE"))
        XCTAssertTrue(BPHomebrewInterface.brewCommandChangesCatalogMembership("Tap"))
    }
}
