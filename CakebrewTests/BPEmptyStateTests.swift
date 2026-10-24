//
//  BPEmptyStateTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPEmptyStateTests: XCTestCase, @unchecked Sendable {

    func testTheHappyPathHasItsOwnWording() {
        let state = BPEmptyState.state(forSidebarRow: Int(FormulaeSideBarItem.outdated.rawValue), searching: false)

        XCTAssertEqual(state.titleKey, "Empty_Outdated_Title")
        XCTAssertEqual(state.messageKey, "Empty_Outdated_Message")
        XCTAssertFalse(state.symbolName.isEmpty)
    }

    func testSearchingTakesPrecedenceOverWhicheverRowIsSelected() {
        let state = BPEmptyState.state(forSidebarRow: Int(FormulaeSideBarItem.all.rawValue), searching: true)

        XCTAssertEqual(state.titleKey, "Empty_Search_Title")
    }

    func testEachListHasItsOwnState() {
        let expected: [FormulaeSideBarItem: String] = [
            .outdated:       "Empty_Outdated_Title",
            .pinned:         "Empty_Pinned_Title",
            .services:       "Empty_Services_Title",
            .installedCasks: "Empty_Casks_Title",
            .outdatedCasks:  "Empty_OutdatedCasks_Title",
            .unifiedUpdates: "Empty_Outdated_Title",
            .leaves:         "Empty_Leaves_Title"
        ]

        for (row, key) in expected {
            let state = BPEmptyState.state(forSidebarRow: Int(row.rawValue), searching: false)
            XCTAssertEqual(state.titleKey, key, "row \(row.rawValue)")
        }
    }

    func testAListWithNoSpecificWordingStillGetsAState() {
        let state = BPEmptyState.state(forSidebarRow: Int(FormulaeSideBarItem.installed.rawValue), searching: false)

        XCTAssertFalse(state.titleKey.isEmpty)
    }

    func testNothingIsShownWhileTheListIsStillLoading() {
        XCTAssertFalse(BPEmptyState.shouldShow(forRowCount: 0, loading: true))
        XCTAssertTrue(BPEmptyState.shouldShow(forRowCount: 0, loading: false))
    }

    func testNothingIsShownWhenThereAreRows() {
        XCTAssertFalse(BPEmptyState.shouldShow(forRowCount: 3, loading: false))
        XCTAssertFalse(BPEmptyState.shouldShow(forRowCount: 3, loading: true))
    }
}
