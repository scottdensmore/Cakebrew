//
//  BPPreferencesTests.swift
//  CakebrewTests
//
//  Tests for BPPreferences (registered defaults + typed accessors) and for
//  the one setting with immediate effect: greedy cask upgrades threading
//  --greedy into the outdated-casks list call.
//

import AppKit
import XCTest

@MainActor
final class BPPreferencesTests: XCTestCase, @unchecked Sendable {

    override func setUp() {
        super.setUp()
        BPPreferences.registerDefaults()
    }

    override func tearDown() {
        // Remove any explicit values so tests observe the registered defaults.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: BPPreferences.backgroundCheckEnabledKey)
        defaults.removeObject(forKey: BPPreferences.backgroundCheckIntervalKey)
        defaults.removeObject(forKey: BPPreferences.greedyCaskUpgradesKey)
        defaults.removeObject(forKey: BPPreferences.automaticAppUpdateCheckEnabledKey)
        defaults.removeObject(forKey: BPPreferences.showMenuBarExtraKey)
        super.tearDown()
    }

    func testRegisteredDefaults() {
        XCTAssertTrue(BPPreferences.backgroundCheckEnabled, "background checking defaults to on")
        XCTAssertEqual(BPPreferences.backgroundCheckInterval, 21600.0, "default interval is 6 hours")
        XCTAssertFalse(BPPreferences.greedyCaskUpgrades, "greedy cask upgrades default to off")
        XCTAssertTrue(BPPreferences.automaticAppUpdateCheckEnabled, "automatic app update check defaults to on")
        XCTAssertFalse(BPPreferences.showMenuBarExtra, "menu bar extra defaults to off")
    }

    func testSettersRoundTrip() {
        BPPreferences.backgroundCheckEnabled = false
        XCTAssertFalse(BPPreferences.backgroundCheckEnabled)

        BPPreferences.backgroundCheckInterval = 3600.0
        XCTAssertEqual(BPPreferences.backgroundCheckInterval, 3600.0)

        BPPreferences.greedyCaskUpgrades = true
        XCTAssertTrue(BPPreferences.greedyCaskUpgrades)

        BPPreferences.automaticAppUpdateCheckEnabled = false
        XCTAssertFalse(BPPreferences.automaticAppUpdateCheckEnabled)

        BPPreferences.showMenuBarExtra = true
        XCTAssertTrue(BPPreferences.showMenuBarExtra)
    }

    func testOutdatedCasksCallOmitsGreedyByDefault() {
        let call = BPHomebrewInterfaceListCallOutdatedCasks()
        let args = call.arguments as? [String] ?? []
        XCTAssertFalse(args.contains("--greedy"))
    }

    func testOutdatedCasksCallAddsGreedyWhenEnabled() {
        BPPreferences.greedyCaskUpgrades = true

        let call = BPHomebrewInterfaceListCallOutdatedCasks()
        XCTAssertEqual(call.arguments as? [String], ["outdated", "--cask", "--verbose", "--greedy"])
    }

    // MARK: - last selected sidebar row

    func testLastSelectedSidebarRowRoundTrips() {
        BPPreferences.lastSelectedSidebarRow = Int(FormulaeSideBarItem.allCasks.rawValue)
        XCTAssertEqual(BPPreferences.lastSelectedSidebarRow, Int(FormulaeSideBarItem.allCasks.rawValue))
    }

    func testLastSelectedSidebarRowDefaultsToInstalled() {
        // A first launch has nothing stored; the app should open where it always has.
        UserDefaults.standard.removeObject(forKey: "BPLastSelectedSidebarRow")
        XCTAssertEqual(BPPreferences.lastSelectedSidebarRow, Int(FormulaeSideBarItem.installed.rawValue))
    }

    // MARK: - restoring that row safely

    func testAStoredRowIsRestoredWhenItIsStillValid() {
        XCTAssertEqual(
            BPSideBarController.restorableRow(from: Int(FormulaeSideBarItem.services.rawValue), rowCount: 15),
            .services
        )
    }

    func testARowPastTheEndFallsBackToInstalled() {
        // Rows are outline indices, so removing a sidebar item can strand a stored
        // value past the end.
        XCTAssertEqual(BPSideBarController.restorableRow(from: 99, rowCount: 15), .installed)
        XCTAssertEqual(BPSideBarController.restorableRow(from: 15, rowCount: 15), .installed)
    }

    func testANegativeRowFallsBackToInstalled() {
        XCTAssertEqual(BPSideBarController.restorableRow(from: -1, rowCount: 15), .installed)
    }

    func testAGroupHeaderRowFallsBackToInstalled() {
        // Category rows are headers, not destinations; restoring onto one would
        // leave the app showing nothing.
        let groups: [FormulaeSideBarItem] = [.formulaeCategory, .casksCategory, .toolsCategory]
        for group in groups {
            XCTAssertEqual(
                BPSideBarController.restorableRow(from: Int(group.rawValue), rowCount: 15),
                .installed,
                "row \(group.rawValue) is a group header"
            )
        }
    }

    // MARK: - remembered sort

    func testSortSelectionRoundTrips() {
        BPPreferences.sortColumnIdentifier = "Version"
        BPPreferences.sortAscending = false

        XCTAssertEqual(BPPreferences.sortColumnIdentifier, "Version")
        XCTAssertFalse(BPPreferences.sortAscending)
    }

    func testClearingTheSortColumnRestoresBrewsNaturalOrder() {
        // Nil means "no sort applied", which is not the same as sorting by an empty
        // key — the list should come back in the order brew returned.
        BPPreferences.sortColumnIdentifier = "Name"
        BPPreferences.sortColumnIdentifier = nil

        XCTAssertNil(BPPreferences.sortColumnIdentifier)
    }

    // MARK: - cask zap

    func testZapChoiceRoundTripsAndDefaultsToOff() {
        // Off by default: zap deletes preferences and support files, not just the
        // app, so it should never be the silent default.
        UserDefaults.standard.removeObject(forKey: "BPZapCasksOnUninstall")
        BPPreferences.registerDefaults()
        XCTAssertFalse(BPPreferences.zapCasksOnUninstall)

        BPPreferences.zapCasksOnUninstall = true
        XCTAssertTrue(BPPreferences.zapCasksOnUninstall)
    }

    func testCheckForUpdatesMenuItemInstallsIdempotentlyBelowAbout() {
        let appMenu = NSMenu(title: NSLocalizedString("Cakebrew", comment: "Test application menu title"))
        appMenu.addItem(withTitle: NSLocalizedString("About Cakebrew", comment: "Test about menu item title"), action: nil, keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: NSLocalizedString("Settings…", comment: "Test settings menu item title"), action: nil, keyEquivalent: ",")

        let target = NSObject()
        let first = BPAppDelegate.installCheckForUpdatesMenuItem(inApplicationMenu: appMenu, target: target)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.action, #selector(BPAppDelegate.checkForAppUpdates(_:)))
        XCTAssertTrue(first?.target === target)
        XCTAssertEqual(first?.accessibilityIdentifier(), "menu.app.checkForUpdates")
        if let first {
            XCTAssertEqual(appMenu.index(of: first), 1)
        }

        let second = BPAppDelegate.installCheckForUpdatesMenuItem(inApplicationMenu: appMenu, target: target)
        XCTAssertEqual(first, second, "installing Check for Updates twice must not duplicate the menu item")
        XCTAssertEqual(appMenu.numberOfItems, 4)
    }

    func testCommandPaletteMenuItemInstallsIdempotentlyAtTopOfToolsMenu() {
        let toolsMenu = NSMenu(title: NSLocalizedString("Sidebar_VoiceOver_Tools", comment: "Test tools menu title"))
        toolsMenu.addItem(withTitle: NSLocalizedString("Toolbar_Homebrew_Update", comment: "Test update menu item title"), action: nil, keyEquivalent: "u")

        let target = NSObject()
        let first = BPAppDelegate.installCommandPaletteMenuItem(inToolsMenu: toolsMenu, target: target)
        XCTAssertNotNil(first)
        XCTAssertEqual(first?.action, NSSelectorFromString("showCommandPalette:"))
        XCTAssertTrue(first?.target === target)
        XCTAssertEqual(first?.keyEquivalent, "k")
        XCTAssertEqual(first?.accessibilityIdentifier(), "menu.tools.commandPalette")
        if let first {
            XCTAssertEqual(toolsMenu.index(of: first), 0)
        }

        let second = BPAppDelegate.installCommandPaletteMenuItem(inToolsMenu: toolsMenu, target: target)
        XCTAssertEqual(first, second, "installing Command Palette twice must not duplicate the menu item")
    }
}
