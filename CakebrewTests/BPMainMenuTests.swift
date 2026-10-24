//
//  BPMainMenuTests.swift
//  CakebrewTests
//

import AppKit
import Foundation
import XCTest

private func BPSearchPackageInput(_ cask: Bool) -> String {
    cask ? "MockChrome" : "MockWget"
}

@objc(BPSearchToolbarController)
private final class BPSearchToolbarController: NSObject {
    @objc var lastSearch: String?
    @objc var searchCount: UInt = 0

    @objc(performSearchWithString:)
    func performSearch(withString search: String) {
        lastSearch = search.lowercased()
        searchCount += 1
    }
}

@MainActor
final class BPMainMenuTests: XCTestCase, @unchecked Sendable {

    private func mainMenuXib() -> String {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = repoRoot.appendingPathComponent("Cakebrew/Base.lproj/MainMenu.xib").path
        let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        XCTAssertFalse(contents.isEmpty, "could not read MainMenu.xib at \(path)")
        return contents
    }

    private func countOfPattern(_ pattern: String, in text: String) -> Int {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return 0
        }
        return regex.numberOfMatches(in: text, options: [], range: NSRange(location: 0, length: (text as NSString).length))
    }

    // MARK: - the duplicate Command-F

    func testCommandFIsBoundExactlyOnce() {
        let bindings = countOfPattern("keyEquivalent=\"f\"", in: mainMenuXib())
        XCTAssertEqual(bindings, 1, "⌘F must be claimed by exactly one menu item")
    }

    func testTheSurvivingCommandFIsSearchForFormula() {
        let match = countOfPattern("title=\"Search for Formula\" keyEquivalent=\"f\"", in: mainMenuXib())
        XCTAssertEqual(match, 1, "⌘F should belong to Search for Formula")
    }

    // MARK: - dead template submenus

    func testTemplateEditSubmenusAreGone() {
        let xib = mainMenuXib()
        for submenu in ["Find", "Spelling and Grammar", "Substitutions", "Transformations", "Speech"] {
            let pattern = "<menu key=\"submenu\" title=\"\(submenu)\""
            XCTAssertEqual(
                countOfPattern(pattern, in: xib),
                0,
                "the \(submenu) submenu targets text actions no view here implements"
            )
        }
    }

    // MARK: - Settings, not Preferences

    func testTheMenuItemMatchesTheWindowItOpens() {
        let xib = mainMenuXib()
        XCTAssertEqual(
            countOfPattern("title=\"Preferences…\"", in: xib),
            0,
            "the window this opens is titled Settings, and macOS 13+ says Settings"
        )
        XCTAssertEqual(countOfPattern("title=\"Settings…\"", in: xib), 1)
    }

    // MARK: - Show/Hide Sidebar

    func testAMenuItemTogglesTheSidebar() {
        let xib = mainMenuXib()
        XCTAssertEqual(
            countOfPattern("selector=\"toggleSidebar:\"", in: xib),
            1,
            "View needs a Show/Hide Sidebar item"
        )
        XCTAssertEqual(
            countOfPattern("title=\"Show Sidebar\" keyEquivalent=\"s\"", in: xib),
            1,
            "the sidebar item should carry the standard ⌃⌘S"
        )
    }

    func testTheWindowControllerHandlesToggleSidebar() {
        XCTAssertTrue(BPMainWindowController.instancesRespond(to: #selector(BPMainWindowController.toggleSidebar(_:))))
    }

    func testTheToolbarOffersTheSidebarButton() {
        let toolbar = BPToolbar(identifier: NSToolbar.Identifier("BPMainWindowToolbarTest"))

        XCTAssertTrue(
            toolbar.toolbarDefaultItemIdentifiers(toolbar).contains(.toggleSidebar),
            "the sidebar button should be present by default"
        )
        XCTAssertTrue(toolbar.toolbarAllowedItemIdentifiers(toolbar).contains(.toggleSidebar))
    }

    // MARK: - toolbar customization

    private func searchItem(for toolbar: BPToolbar) -> NSSearchToolbarItem {
        toolbar.toolbar(
            toolbar,
            itemForItemIdentifier: NSToolbarItem.Identifier("toolbarItemSearch"),
            willBeInsertedIntoToolbar: true
        ) as! NSSearchToolbarItem
    }

    func testSearchUnlockEnablesTheFieldWithoutEnablingInactiveActions() {
        let toolbar = BPToolbar(identifier: NSToolbar.Identifier("SearchEnablement"))
        let controller = BPSearchToolbarController()
        toolbar.controller = controller
        let item = searchItem(for: toolbar)
        XCTAssertFalse(item.isEnabled, "Search starts locked during the initial load")
        XCTAssertFalse(item.searchField.isEnabled)
        toolbar.unlockItems()
        item.validate()
        toolbar.validateVisibleItems()
        XCTAssertTrue(item.isEnabled, "Search must be available after loading")
        XCTAssertTrue(item.searchField.isEnabled, "An existing but disabled field cannot be clicked")
        for identifier in ["toolbarItemInformation", "toolbarItemMultiAction"] {
            let placeholder = toolbar.toolbar(
                toolbar,
                itemForItemIdentifier: NSToolbarItem.Identifier(identifier),
                willBeInsertedIntoToolbar: true
            )
            XCTAssertFalse(placeholder?.isEnabled ?? true, "Inactive slots must stay disabled")
        }
        toolbar.lockItems()
    }

    func testSearchLockAndUnlockSurviveValidationAndMissingController() {
        let toolbar = BPToolbar(identifier: NSToolbar.Identifier("SearchLocking"))
        let controller = BPSearchToolbarController()
        toolbar.controller = controller
        let item = searchItem(for: toolbar)
        toolbar.unlockItems()
        toolbar.lockItems()
        item.validate()
        XCTAssertFalse(item.isEnabled)
        XCTAssertFalse(item.searchField.isEnabled)
        toolbar.unlockItems()
        item.validate()
        XCTAssertTrue(item.isEnabled)
        XCTAssertTrue(item.searchField.isEnabled)
        toolbar.controller = nil
        toolbar.unlockItems()
        item.validate()
        XCTAssertFalse(item.isEnabled, "Search has no destination without a controller")
        XCTAssertFalse(item.searchField.isEnabled)
    }

    func testSearchTextChangesAndSubmissionDeliverStringsToTheController() {
        let toolbar = BPToolbar(identifier: NSToolbar.Identifier("SearchDelivery"))
        let controller = BPSearchToolbarController()
        toolbar.controller = controller
        toolbar.unlockItems()
        let field = searchItem(for: toolbar).searchField
        XCTAssertEqual(toolbar.searchField, field)
        XCTAssertTrue(field.delegate === toolbar)
        field.stringValue = BPSearchPackageInput(false)
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        XCTAssertEqual(controller.lastSearch, "mockwget")
        XCTAssertEqual(controller.searchCount, 1)
        field.stringValue = BPSearchPackageInput(true)
        XCTAssertNotNil(field.action, "Submitting or clearing Search needs a safe action")
        if let action = field.action {
            _ = NSApplication.shared.sendAction(action, to: field.target, from: field)
        }
        XCTAssertEqual(controller.lastSearch, "mockchrome")
        XCTAssertEqual(controller.searchCount, 2)
        field.stringValue = ""
        if let action = field.action {
            _ = NSApplication.shared.sendAction(action, to: field.target, from: field)
        }
        XCTAssertEqual(controller.lastSearch, "", "Clearing Search must reset the filter")
        toolbar.lockItems()
    }

    func testToolbarCustomizationIsNotHalfWired() {
        let toolbar = BPToolbar(identifier: NSToolbar.Identifier("BPMainWindowToolbarTest"))
        XCTAssertFalse(
            toolbar.allowsUserCustomization,
            "either wire customization fully or don't advertise it"
        )
    }

    // MARK: - Help that actually helps

    func testHelpDoesNotSendShowHelpWithNoHelpBook() {
        XCTAssertEqual(countOfPattern("selector=\"showHelp:\"", in: mainMenuXib()), 0)
    }

    func testHelpOpensTheDocumentation() {
        let xib = mainMenuXib()
        XCTAssertEqual(countOfPattern("selector=\"openDocumentation:\"", in: xib), 1)
        XCTAssertEqual(
            countOfPattern("title=\"Cakebrew Documentation\"", in: xib),
            1,
            "the title should say what the item does, since it opens a web page"
        )
    }

    func testLocalizedUpgradeAllResourceDescribesBothNamespacesAndConfirmation() {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        var resources = repoRoot.appendingPathComponent("Cakebrew").path
        if let appPath = ProcessInfo.processInfo.environment["CAKEBREW_TEST_APP_BUNDLE"] {
            let app = Bundle(path: appPath)
            XCTAssertNotNil(app, "Explicit packaged-app validation must never fall back to source resources")
            guard let resourcePath = app?.resourcePath else { return }
            resources = resourcePath
        }
        let formulaTerms = [
            "de": "Formeln",
            "fr": "formules",
            "it": "formule",
            "pt": "Fórmulas",
            "zh-Hans": "Formulae"
        ]
        for (locale, term) in formulaTerms {
            let path = (resources as NSString).appendingPathComponent("\(locale).lproj")
            let localized = Bundle(path: path)
            XCTAssertNotNil(localized, "Missing localized resources for \(locale)")
            let title = localized?.localizedString(forKey: "DdP-fd-ccO.title", value: "MISSING", table: "MainMenu") ?? "MISSING"
            XCTAssertNotEqual(title, "MISSING", "\(locale) must resolve its own menu override")
            XCTAssertTrue(title.localizedCaseInsensitiveContains(term), "\(locale) title must retain formula scope: \(title)")
            XCTAssertTrue(title.contains("Casks"), "\(locale) title must include the cask scope: \(title)")
            XCTAssertTrue(title.hasSuffix("…"), "\(locale) action opens confirmation before running: \(title)")
        }
    }
}
