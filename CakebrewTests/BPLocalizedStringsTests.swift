//
//  BPLocalizedStringsTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

@MainActor
final class BPLocalizedStringsTests: XCTestCase, @unchecked Sendable {

    // MARK: - sidebar description

    func testEverySelectableSidebarRowHasItsOwnDescription() {
        let expected: [FormulaeSideBarItem: String] = [
            .installed:      "Sidebar_Info_Installed",
            .outdated:       "Sidebar_Info_Outdated",
            .all:            "Sidebar_Info_All",
            .leaves:         "Sidebar_Info_Leaves",
            .pinned:         "Sidebar_Info_Pinned",
            .repositories:   "Sidebar_Info_Repos",
            .installedCasks: "Sidebar_Info_Casks",
            .outdatedCasks:  "Sidebar_Info_OutdatedCasks",
            .allCasks:       "Sidebar_Info_AllCasks",
            .doctor:         "Sidebar_Info_Doctor",
            .update:         "Sidebar_Info_Update",
            .services:       "Sidebar_Info_Services",
            .unifiedUpdates: "Sidebar_Info_Unified_Updates"
        ]

        for (row, key) in expected {
            XCTAssertEqual(
                BPSideBarController.infoKey(forRow: Int(row.rawValue)),
                key,
                "row \(row.rawValue)"
            )
        }
    }

    func testGroupHeaderRowsHaveNoDescription() {
        XCTAssertNil(BPSideBarController.infoKey(forRow: Int(FormulaeSideBarItem.formulaeCategory.rawValue)))
        XCTAssertNil(BPSideBarController.infoKey(forRow: Int(FormulaeSideBarItem.casksCategory.rawValue)))
        XCTAssertNil(BPSideBarController.infoKey(forRow: Int(FormulaeSideBarItem.toolsCategory.rawValue)))
    }

    func testAnUnknownRowHasNoDescription() {
        XCTAssertNil(BPSideBarController.infoKey(forRow: 99))
        XCTAssertNil(BPSideBarController.infoKey(forRow: -1))
    }

    // MARK: - service status

    func testEveryServiceStatusHasALocalizedName() {
        let expected: [BPServiceStatus: String] = [
            .none:      "Services_Status_None",
            .started:   "Services_Status_Started",
            .stopped:   "Services_Status_Stopped",
            .error:     "Services_Status_Error",
            .scheduled: "Services_Status_Scheduled",
            .unknown:   "Services_Status_Unknown"
        ]

        for (status, key) in expected {
            XCTAssertEqual(BPService.localizationKey(for: status), key, "status \(status.rawValue)")
        }
    }

    func testAnUnrecognisedStatusFallsBackToUnknown() {
        let unknown = unsafeBitCast(42 as Int, to: BPServiceStatus.self)
        XCTAssertEqual(BPService.localizationKey(for: unknown), "Services_Status_Unknown")
    }

    func testTheStatusNameNeverEchoesBrewsRawToken() {
        for raw in ["none", "started", "stopped", "error", "scheduled"] {
            let status = BPService.status(from: raw)
            let name = BPService.localizedName(for: status)
            XCTAssertNotEqual(name, raw, "\(raw) reached the UI unlocalized")
        }
    }
}
