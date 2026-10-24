//
//  BPAccessibilityTests.swift
//  CakebrewTests
//
//  The sidebar badges are the app's main information signal and are painted
//  with drawAtPoint:withAttributes:, so nothing about them reached the
//  accessibility tree until BPSidebarBadgeView declared a role and a value.
//

import AppKit
import XCTest

@MainActor
final class BPAccessibilityTests: XCTestCase, @unchecked Sendable {

    func testTheBadgeIsAnAccessibilityElementWithItsCountAsTheValue() {
        let badge = BPSidebarBadgeView(frame: NSRect(x: 0, y: 0, width: 30, height: 16))
        badge.badgeValue = 42

        XCTAssertTrue(badge.isAccessibilityElement(), "a view painted with drawAtPoint: is invisible otherwise")
        XCTAssertEqual(badge.accessibilityRole(), .staticText)
        let valueDesc = String(describing: badge.accessibilityValue() ?? "")
        XCTAssertTrue(valueDesc.contains("42"), "the count is the point of the badge: \(valueDesc)")
    }

    func testAZeroBadgeStillAnnouncesItsCount() {
        let badge = BPSidebarBadgeView(frame: NSRect(x: 0, y: 0, width: 30, height: 16))
        badge.badgeValue = 0

        let valueDesc = String(describing: badge.accessibilityValue() ?? "")
        XCTAssertTrue(valueDesc.contains("0"))
    }

    // MARK: - Row labels

    func testARowIsAnnouncedWithItsGroupSoDuplicatesDiffer() {
        let formulae = BPSideBarController.accessibilityLabel(
            forGroup: "Formulae",
            title: "Installed",
            badge: NSNumber(value: 3)
        )
        let casks = BPSideBarController.accessibilityLabel(
            forGroup: "Casks",
            title: "Installed",
            badge: NSNumber(value: 2)
        )

        XCTAssertNotEqual(formulae, casks, "the two Installed rows must not sound alike")
        XCTAssertTrue(formulae.contains("Formulae"))
        XCTAssertTrue(formulae.contains("Installed"))
        XCTAssertTrue(formulae.contains("3"), "the count is the row's main signal")
    }

    func testAnAbsentBadgeIsOmittedRatherThanAnnouncedAsMinusOne() {
        let label = BPSideBarController.accessibilityLabel(
            forGroup: "Tools",
            title: "Doctor",
            badge: NSNumber(value: -1)
        )

        XCTAssertFalse(label.contains("-1"), "got: \(label)")
        XCTAssertTrue(label.contains("Doctor"))
        XCTAssertTrue(label.contains("Tools"))
    }

    func testAZeroBadgeIsStillAnnounced() {
        let label = BPSideBarController.accessibilityLabel(
            forGroup: "Formulae",
            title: "Outdated",
            badge: NSNumber(value: 0)
        )

        XCTAssertTrue(label.contains("0"), "nothing outdated is worth hearing: \(label)")
    }

    func testAGrouplessRowIsAnnouncedByTitleAlone() {
        let label = BPSideBarController.accessibilityLabel(
            forGroup: nil,
            title: "Doctor",
            badge: NSNumber(value: -1)
        )

        XCTAssertEqual(label, "Doctor")
    }

    func testTheLabelNeverLeaksALocalizationKey() {
        let label = BPSideBarController.accessibilityLabel(
            forGroup: "Casks",
            title: "Outdated",
            badge: NSNumber(value: 1)
        )

        XCTAssertFalse(label.contains("Sidebar_"), "got: \(label)")
    }

    // MARK: - Row identifiers

    func testEverySelectableRowHasAUniqueUnlocalizedIdentifier() {
        let controller = BPSideBarController()
        let identifiers = controller.selectableRowAccessibilityIdentifiers()

        XCTAssertEqual(identifiers.count, Set(identifiers).count, "identifiers must be unique: \(identifiers)")
        XCTAssertGreaterThanOrEqual(identifiers.count, 12, "expected every selectable row, got \(identifiers)")

        for identifier in identifiers {
            XCTAssertTrue(identifier.hasPrefix("sidebar."), "\(identifier) is not namespaced")
            XCTAssertEqual(identifier, identifier.lowercased(), "\(identifier) should be stable and lowercase")
        }

        XCTAssertTrue(identifiers.contains("sidebar.formulae.installed"), "\(identifiers)")
        XCTAssertTrue(identifiers.contains("sidebar.casks.installed"), "\(identifiers)")
        XCTAssertTrue(identifiers.contains("sidebar.tools.updates"), "\(identifiers)")
    }
}
