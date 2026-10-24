//
//  CakebrewUITests.swift
//  CakebrewUITests
//
//  End-to-end UI tests that drive the real app via XCUITest.
//

import XCTest

@MainActor
final class CakebrewUITests: XCTestCase, @unchecked Sendable {
    var app: XCUIApplication!
    var brewfileFixtureDirectory: URL?

    private func stringValue(of element: XCUIElement) -> String {
        (element.value as? String) ?? ""
    }

    func openAutoremove(withArguments arguments: [String]) {
        launch(withArguments: ["-BPMockBrew"] + arguments)
        app.menuBars.menuBarItems["Tools"].click()
        app.menuItems["Remove Unused Dependencies…"].click()
        XCTAssertTrue(app.sheets.firstMatch.textViews["autoremove.output"].waitForExistence(timeout: 10))
    }

    func testAutoremoveReviewedRemovalStreamsAndFinishes() {
        openAutoremove(withArguments: [])
        let remove = app.sheets.firstMatch.buttons["autoremove.remove"]
        expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: remove)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(stringValue(of: app.textViews["autoremove.output"]).contains("mockunused"))
        remove.click()
        let status = app.staticTexts["autoremove.status"]
        expectation(for: NSPredicate(format: "value CONTAINS 'were removed'"), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(stringValue(of: app.textViews["autoremove.output"]).contains("MOCK_AUTOREMOVE_OK"))
        XCTAssertTrue(app.sheets.firstMatch.buttons["autoremove.cancel"].isEnabled)
    }

    func testAutoremoveReviewCancellationDoesNotRunRemoval() {
        openAutoremove(withArguments: [])
        let remove = app.sheets.firstMatch.buttons["autoremove.remove"]
        expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: remove)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(stringValue(of: app.textViews["autoremove.output"]).contains("MOCK_AUTOREMOVE_STARTED"))
        app.sheets.firstMatch.buttons["autoremove.cancel"].click()
        expectation(for: NSPredicate(format: "exists == NO"), evaluatedWith: app.sheets.firstMatch)
        waitForExpectations(timeout: 5)
    }

    func testAutoremoveIncompleteRefreshRemainsVisibleAfterRemoval() {
        openAutoremove(withArguments: ["-BPMockFailedAutoremoveRefresh"])
        let remove = app.sheets.firstMatch.buttons["autoremove.remove"]
        expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: remove)
        waitForExpectations(timeout: 10)
        remove.click()
        expectation(
            for: NSPredicate(format: "value CONTAINS 'could not be refreshed'"),
            evaluatedWith: app.staticTexts["autoremove.status"]
        )
        waitForExpectations(timeout: 10)
        XCTAssertTrue(stringValue(of: app.textViews["autoremove.output"]).contains("MOCK_AUTOREMOVE_OK"))
        XCTAssertTrue(app.sheets.firstMatch.buttons["autoremove.cancel"].isEnabled)
    }

    func testAutoremoveEmptyPreviewDoesNotEnableRemoval() {
        openAutoremove(withArguments: ["-BPMockEmptyAutoremove"])
        expectation(
            for: NSPredicate(format: "value CONTAINS 'No unused'"),
            evaluatedWith: app.staticTexts["autoremove.status"]
        )
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.sheets.firstMatch.buttons["autoremove.remove"].isEnabled)
    }

    func testAutoremoveMalformedPreviewDoesNotEnableRemoval() {
        openAutoremove(withArguments: ["-BPMockInvalidAutoremove"])
        expectation(
            for: NSPredicate(format: "value CONTAINS 'could not'"),
            evaluatedWith: app.staticTexts["autoremove.status"]
        )
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.sheets.firstMatch.buttons["autoremove.remove"].isEnabled)
        XCTAssertTrue(stringValue(of: app.textViews["autoremove.output"]).contains("MOCK_UNRECOGNIZED"))
    }

    func testAutoremoveActiveCancellationReportsPartialChanges() {
        openAutoremove(withArguments: ["-BPMockSlowAutoremove"])
        let remove = app.sheets.firstMatch.buttons["autoremove.remove"]
        expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: remove)
        waitForExpectations(timeout: 10)
        remove.click()
        expectation(
            for: NSPredicate(format: "value CONTAINS 'MOCK_AUTOREMOVE_STARTED'"),
            evaluatedWith: app.textViews["autoremove.output"]
        )
        waitForExpectations(timeout: 10)
        app.sheets.firstMatch.buttons["autoremove.cancel"].click()
        expectation(
            for: NSPredicate(format: "value CONTAINS 'partially removed'"),
            evaluatedWith: app.staticTexts["autoremove.status"]
        )
        waitForExpectations(timeout: 10)
        XCTAssertFalse(stringValue(of: app.textViews["autoremove.output"]).contains("MOCK_AUTOREMOVE_OK"))
    }

    func testAutoremoveChangedPreviewCannotRunRemoval() {
        openAutoremove(withArguments: ["-BPMockChangedAutoremove"])
        let remove = app.sheets.firstMatch.buttons["autoremove.remove"]
        expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: remove)
        waitForExpectations(timeout: 10)
        remove.click()
        expectation(
            for: NSPredicate(format: "value CONTAINS 'list changed'"),
            evaluatedWith: app.staticTexts["autoremove.status"]
        )
        waitForExpectations(timeout: 10)
        XCTAssertFalse(stringValue(of: app.textViews["autoremove.output"]).contains("MOCK_AUTOREMOVE_STARTED"))
    }

    func testAutoremoveFailureKeepsDiagnosticsVisible() {
        openAutoremove(withArguments: ["-BPMockFailedAutoremove"])
        let remove = app.sheets.firstMatch.buttons["autoremove.remove"]
        expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: remove)
        waitForExpectations(timeout: 10)
        remove.click()
        expectation(
            for: NSPredicate(format: "value CONTAINS 'Removal failed'"),
            evaluatedWith: app.staticTexts["autoremove.status"]
        )
        waitForExpectations(timeout: 10)
        XCTAssertTrue(stringValue(of: app.textViews["autoremove.output"]).contains("MOCK_AUTOREMOVE_FAILED"))
        XCTAssertFalse(stringValue(of: app.textViews["autoremove.output"]).contains("MOCK_AUTOREMOVE_OK"))
    }

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
        continueAfterFailure = false
        app = XCUIApplication()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
        app.terminate()
        if let dir = brewfileFixtureDirectory {
            try? FileManager.default.removeItem(at: dir)
        }
        brewfileFixtureDirectory = nil
        app = nil
        }
        super.tearDown()
    }

    // Launch the app with the given arguments and wait for its main window.
    func launch(withArguments arguments: [String]) {
        // The app now reopens on the sidebar row the user last used, which makes a
        // launch depend on whatever the previous test left behind. Pin it through
        // the argument domain (which outranks stored defaults) so every journey
        // starts on Installed; testReopensOnTheLastUsedSidebarRow overrides it
        // deliberately to exercise the restore.
        // Both of these change what the app shows at launch, so both are pinned
        // through the argument domain rather than inherited from whatever the last
        // run (or the developer's own session) left stored.
        let pinned = ["-BPLastSelectedSidebarRow", "1", "-BPSortColumnIdentifier", ""]
        let alreadyPinned = arguments.contains("-BPLastSelectedSidebarRow")
        app.launchArguments = alreadyPinned ? arguments : (arguments + pinned)
        app.launch()
        XCTAssertTrue(
            app.windows.firstMatch.waitForExistence(timeout: 30.0),
            "the main window should appear after launch"
        )

        // A test that pins a different starting row is not going to land on the
        // Installed list, so the settle-wait below would never be satisfied.
        let rowIndex = arguments.firstIndex(of: "-BPLastSelectedSidebarRow")
        let startsOnInstalled: Bool
        if let rowIndex, rowIndex + 1 < arguments.count {
            startsOnInstalled = (arguments[rowIndex + 1] == "1")
        } else {
            startsOnInstalled = true
        }
        if !startsOnInstalled {
            return
        }

        // Under the mock, wait for the initial reload to settle before tests
        // navigate: homebrewManagerFinishedUpdating reloads the sidebar and
        // re-selects the last selection, which can clobber a click that lands
        // mid-reload (the source of moving sidebar-navigation flakes on CI).
        // The launch view is Installed, so mockwget rendering means the initial
        // refresh cycle is done.
        if arguments.contains("-BPMockBrew") {
            XCTAssertTrue(
                formulaCell(withName: "mockwget").waitForExistence(timeout: 30.0),
                "the initial Installed list should render after launch"
            )
        }
    }

    func sidebar() -> XCUIElement {
        let outline = app.outlines.firstMatch
        XCTAssertTrue(outline.waitForExistence(timeout: 30.0), "the sidebar outline should appear")
        return outline
    }

    /// Addresses a sidebar row by its accessibility identifier. The rows carry
    /// stable, unlocalized identifiers precisely so journeys stop disambiguating
    /// duplicate titles by index — "Installed" and "Outdated" each appear under
    /// both Formulae and Casks.
    func sidebarRow(_ identifier: String) -> XCUIElement {
        sidebar().staticTexts[identifier]
    }

    // Dismiss a confirmation alert sheet with Escape. Avoids matching the ambiguous
    // "Cancel" button (the toolbar search field also exposes one) and leaves a clean
    // state for teardown.
    func dismissConfirmationSheet() {
        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Launch / chrome

    // Mouse journeys are valid on headless CI; keyboard routing is exercised by
    // synthetic NSEvents in BPFormulaeTableActionTests and checked locally on macOS.
    func testDoubleClickInstalledFormulaShowsInfoWithoutUninstalling() {
        launch(withArguments: ["-BPMockBrew"])
        formulaCell(withName: "mockwget").doubleClick()
        let info = app.descendants(matching: .any)
            .matching(identifier: "formula.information.text")
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "A mock formula", "A mock formula"))
            .firstMatch
        let appeared = info.waitForExistence(timeout: 15)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared)
        XCTAssertFalse(app.sheets.firstMatch.exists, "Installed primary action is information, not uninstall")
    }

    func testDoubleClickInstalledCaskShowsInfoWithoutUninstalling() {
        launch(withArguments: ["-BPMockBrew"])
        sidebarRow("sidebar.casks.installed").click()
        let cask = formulaCell(withName: "mockchrome")
        XCTAssertTrue(cask.waitForExistence(timeout: 15))
        cask.doubleClick()
        let info = app.descendants(matching: .any)
            .matching(identifier: "formula.information.text")
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "A mock cask", "A mock cask"))
            .firstMatch
        let appeared = info.waitForExistence(timeout: 15)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared)
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testDoubleClickAvailableFormulaUsesInstallConfirmationAndCancel() {
        launch(withArguments: ["-BPMockBrew"])
        sidebarRow("sidebar.formulae.all").click()
        let formula = formulaCell(withName: "mockhtop")
        XCTAssertTrue(formula.waitForExistence(timeout: 15))
        formula.doubleClick()
        let sheet = app.sheets.firstMatch
        let appeared = sheet.buttons["Yes"].waitForExistence(timeout: 15)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared)
        let message = sheet.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "mockhtop")).firstMatch
        XCTAssertTrue(message.exists)
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
        XCTAssertTrue(formula.exists)
        XCTAssertTrue(app.buttons["Install Formula"].exists, "Cancel leaves the selected package uninstalled")
    }

    func testDoubleClickOutdatedFormulaAndCaskUseUpgradeConfirmation() {
        launch(withArguments: ["-BPMockBrew"])
        let rows = ["sidebar.formulae.outdated", "sidebar.casks.outdated"]
        let names = ["mockgit", "mockchrome"]
        for index in 0..<rows.count {
            sidebarRow(rows[index]).click()
            let formula = formulaCell(withName: names[index])
            XCTAssertTrue(formula.waitForExistence(timeout: 15))
            formula.doubleClick()
            let sheet = app.sheets.firstMatch
            let appeared = sheet.buttons["Yes"].waitForExistence(timeout: 15)
            if !appeared {
                NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
            }
            XCTAssertTrue(appeared)
            XCTAssertTrue(sheet.staticTexts["Updating Formulae"].exists)
            let message = sheet.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", names[index])).firstMatch
            XCTAssertTrue(message.exists)
            sheet.buttons["Cancel"].click()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
            XCTAssertTrue(formula.exists)
        }
    }

    func testConfirmedSelectedFormulaAndCaskUpgradesComplete() {
        launch(withArguments: ["-BPMockBrew"])
        let rows = ["sidebar.formulae.outdated", "sidebar.casks.outdated"]
        let names = ["mockgit", "mockchrome"]
        let commands = [
            "MOCK_UPGRADE_ARGUMENTS: upgrade --formula mockgit",
            "MOCK_UPGRADE_ARGUMENTS: upgrade --cask mockchrome"
        ]
        for index in 0..<rows.count {
            sidebarRow(rows[index]).click()
            let formula = formulaCell(withName: names[index])
            XCTAssertTrue(formula.waitForExistence(timeout: 15))
            formula.doubleClick()
            let yes = app.sheets.firstMatch.buttons["Yes"]
            XCTAssertTrue(yes.waitForExistence(timeout: 15))
            yes.click()

            let sheet = app.sheets.firstMatch
            let transcript = NSPredicate(
                format: "value CONTAINS %@ AND value CONTAINS %@",
                "MOCK_UPGRADE_OK",
                commands[index]
            )
            let output = sheet.textViews.matching(transcript).firstMatch
            let appeared = output.waitForExistence(timeout: 15)
            if !appeared {
                NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
            }
            XCTAssertTrue(appeared, "Confirmed selection must execute in its own namespace")
            let ok = sheet.buttons["OK"]
            XCTAssertTrue(ok.waitForExistence(timeout: 15))
            let finished = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == YES"),
                object: ok
            )
            XCTAssertEqual(XCTWaiter.wait(for: [finished], timeout: 15), .completed)
            XCTAssertFalse(sheet.buttons["Cancel"].isEnabled)
            ok.click()
            XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
            XCTAssertTrue(formula.exists, "Mock upgrade leaves the selected fixture available")
        }
        // A new confirmation after the final dismissal proves cleanup released
        // the busy guard, rather than merely hiding the operation window.
        sidebarRow("sidebar.formulae.outdated").click()
        formulaCell(withName: "mockgit").doubleClick()
        let nextSheet = app.sheets.firstMatch
        let nextActionReady = nextSheet.buttons["Yes"].waitForExistence(timeout: 15)
        if !nextActionReady {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(nextActionReady, "Dismissal must permit another upgrade action")
        nextSheet.buttons["Cancel"].click()
        XCTAssertTrue(nextSheet.waitForNonExistence(timeout: 10))
    }

    func testDoubleClickAvailableCaskUsesInstallConfirmationAndCancel() {
        launch(withArguments: ["-BPMockBrew"])
        sidebarRow("sidebar.casks.all").click()
        let cask = formulaCell(withName: "mockfirefox")
        XCTAssertTrue(cask.waitForExistence(timeout: 15))
        cask.doubleClick()
        let sheet = app.sheets.firstMatch
        let appeared = sheet.buttons["Yes"].waitForExistence(timeout: 15)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared)
        let message = sheet.staticTexts.matching(NSPredicate(format: "value CONTAINS %@", "mockfirefox")).firstMatch
        XCTAssertTrue(message.exists)
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
        XCTAssertTrue(cask.exists)
        XCTAssertTrue(app.buttons["Install Formula"].exists)
    }

    func testDoubleClickEmptyTableSpaceDoesNotActOnSelectedFormula() {
        launch(withArguments: ["-BPMockBrew"])
        sidebarRow("sidebar.formulae.all").click()
        let formula = formulaCell(withName: "mockhtop")
        XCTAssertTrue(formula.waitForExistence(timeout: 15))
        formula.click()
        let table = app.tables.firstMatch
        XCTAssertTrue(table.exists)
        var rowsBottom: CGFloat = 0
        let tableRows = table.descendants(matching: .tableRow).allElementsBoundByIndex
        XCTAssertGreaterThan(tableRows.count, 0, "Validate that the row geometry probe found the rendered rows")
        for row in tableRows {
            rowsBottom = max(rowsBottom, row.frame.maxY)
        }
        let y = table.frame.maxY - 8
        XCTAssertGreaterThan(y, rowsBottom, "The click must really be below every row")
        let point = table.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
            .withOffset(CGVector(dx: 20, dy: y - table.frame.minY))
        point.doubleClick()
        XCTAssertFalse(app.sheets.firstMatch.waitForExistence(timeout: 2))
    }

    func openBrewfileReview(withContents contents: String, extraArguments arguments: [String]) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        brewfileFixtureDirectory = dir
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false))
        let file = dir.appendingPathComponent("Brewfile")
        XCTAssertNoThrow(try contents.write(to: file, atomically: true, encoding: .utf8))
        launch(withArguments: ["-BPMockBrew", "-BPMockBrewfileURL", file.path] + arguments)
        app.menuBars.menuBarItems["Brewfile Test"].click()
        app.menuItems["Review Mock Brewfile"].click()
        XCTAssertTrue(app.sheets.firstMatch.buttons["brewfile.review.cancel"].waitForExistence(timeout: 5))
    }

    func testBrewfileReviewShowsGroupedStatusesAndCancelRunsNothing() {
        openBrewfileReview(
            withContents: "brew 'mockwget'\ncask 'missingapp'\ntap 'owner/tap'\nmas 'App', id: 123\nvscode 'pub.ext'",
            extraArguments: []
        )
        let review = stringValue(of: app.sheets.firstMatch.textViews["brewfile.review.entries"])
        XCTAssertTrue(review.contains("mockwget — Installed"))
        XCTAssertTrue(review.contains("missingapp — Missing"))
        XCTAssertTrue(review.contains("Mac App Store"))
        XCTAssertTrue(review.contains("Not checked"))
        app.sheets.firstMatch.buttons["brewfile.review.cancel"].click()
        XCTAssertFalse(app.textViews["brewfile.import.output"].exists)
    }

    func testBrewfileReviewBlocksUnsupportedFiles() {
        openBrewfileReview(withContents: "brew 'mockwget'\nsystem('unsafe')", extraArguments: [])
        XCTAssertFalse(app.sheets.firstMatch.buttons["brewfile.review.install"].isEnabled)
        XCTAssertTrue(stringValue(of: app.sheets.firstMatch.textViews["brewfile.review.entries"]).contains("Line 2"))
        app.sheets.firstMatch.buttons["brewfile.review.cancel"].click()
    }

    func testBrewfileReviewBlocksEmptyFiles() {
        openBrewfileReview(withContents: "# no direct entries\n", extraArguments: [])
        XCTAssertFalse(app.sheets.firstMatch.buttons["brewfile.review.install"].isEnabled)
        XCTAssertTrue(
            stringValue(of: app.sheets.firstMatch.textViews["brewfile.review.entries"])
                .contains("No supported package entries")
        )
        app.sheets.firstMatch.buttons["brewfile.review.cancel"].click()
    }

    func testBrewfileReviewConfirmedImportFinishes() {
        openBrewfileReview(withContents: "brew 'mockwget'\ncask 'mockchrome'", extraArguments: [])
        app.sheets.firstMatch.buttons["brewfile.review.install"].click()
        let status = app.staticTexts["brewfile.import.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        let finished = NSPredicate(format: "value == %@", "Import finished.")
        expectation(for: finished, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(stringValue(of: app.textViews["brewfile.import.output"]).contains("MOCK_IMPORT_OK"))
        app.sheets.firstMatch.buttons["brewfile.import.action"].click()
    }

    func testBrewfileImportCanBeCancelledWhileStreaming() {
        openBrewfileReview(
            withContents: "brew 'mockwget'",
            extraArguments: ["-BPMockHoldBrewfileImportUntilCancelled"]
        )
        app.sheets.firstMatch.buttons["brewfile.review.install"].click()
        let action = app.sheets.firstMatch.buttons["brewfile.import.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        XCTAssertEqual(action.title, "Cancel")
        action.click()
        let status = app.staticTexts["brewfile.import.status"]
        expectation(
            for: NSPredicate(format: "value == %@", "Import cancelled. Some changes may already have been made."),
            evaluatedWith: status
        )
        waitForExpectations(timeout: 10)
        XCTAssertEqual(action.title, "Close")
        let output = stringValue(of: app.textViews["brewfile.import.output"])
        XCTAssertTrue(output.contains("MOCK_IMPORT_STARTED"))
        XCTAssertTrue(output.contains("MOCK_IMPORT_CANCELLED"))
        XCTAssertFalse(output.contains("MOCK_IMPORT_OK"))
        action.click()
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testBrewfileImportFailureRemainsVisible() {
        openBrewfileReview(
            withContents: "brew 'mockwget'",
            extraArguments: ["-BPMockBrewfileImportFails"]
        )
        app.sheets.firstMatch.buttons["brewfile.review.install"].click()
        let status = app.staticTexts["brewfile.import.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        expectation(
            for: NSPredicate(format: "value BEGINSWITH %@", "Import failed."),
            evaluatedWith: status
        )
        waitForExpectations(timeout: 10)
        XCTAssertTrue(stringValue(of: app.textViews["brewfile.import.output"]).contains("MOCK_IMPORT_FAILED"))
        app.sheets.firstMatch.buttons["brewfile.import.action"].click()
    }

    func germanBrewfileArguments() -> [String] {
        ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"]
    }

    func testGermanBrewfileReviewAndCancel() {
        openBrewfileReview(
            withContents: "brew 'mockwget'\ncask 'missingapp'\ntap 'owner/tap'\nmas 'App', id: 123\nvscode 'pub.ext'",
            extraArguments: germanBrewfileArguments()
        )
        let sheet = app.sheets.firstMatch
        let review = stringValue(of: sheet.textViews["brewfile.review.entries"])
        XCTAssertTrue(review.contains("mockwget — Installiert"))
        XCTAssertTrue(review.contains("missingapp — Fehlt"))
        XCTAssertTrue(review.contains("Nicht geprüft"))
        XCTAssertTrue(review.contains("Mac App Store"))
        XCTAssertTrue(sheet.staticTexts["Brewfile prüfen"].exists)
        let warning = NSPredicate(format: "value CONTAINS %@", "Installationsskripte ausführen")
        XCTAssertTrue(sheet.staticTexts.matching(warning).firstMatch.exists)
        XCTAssertEqual(sheet.buttons["brewfile.review.install"].title, "Geprüfte Einträge installieren")
        XCTAssertEqual(sheet.buttons["brewfile.review.cancel"].title, "Abbrechen")
        sheet.buttons["brewfile.review.cancel"].click()
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertFalse(app.textViews["brewfile.import.output"].exists)
    }

    func testGermanBrewfileReviewEscapeRunsNothing() {
        openBrewfileReview(withContents: "brew 'mockwget'", extraArguments: germanBrewfileArguments())
        let sheet = app.sheets.firstMatch
        let cancel = sheet.buttons["brewfile.review.cancel"]
        let localizedReview = sheet.staticTexts["Brewfile prüfen"].exists
            && stringValue(of: sheet.textViews["brewfile.review.entries"]).contains("mockwget — Installiert")
            && cancel.title == "Abbrechen"
        let applicationState = app.state
        XCTAssertTrue(localizedReview)
        XCTAssertEqual(applicationState, .runningForeground)
        guard localizedReview && applicationState == .runningForeground else { return }

        app.typeKey(.escape, modifierFlags: [])
        expectation(
            for: NSPredicate(format: "exists == NO"),
            evaluatedWith: app.sheets.firstMatch
        )
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.sheets.firstMatch.exists)
        XCTAssertFalse(app.textViews["brewfile.import.output"].exists)
        XCTAssertFalse(app.staticTexts["brewfile.import.status"].exists)
    }

    func testGermanBrewfileUnsupportedWarning() {
        openBrewfileReview(
            withContents: "brew 'mockwget'\nsystem('unsafe')",
            extraArguments: germanBrewfileArguments()
        )
        let sheet = app.sheets.firstMatch
        XCTAssertFalse(sheet.buttons["brewfile.review.install"].isEnabled)
        let review = stringValue(of: sheet.textViews["brewfile.review.entries"])
        XCTAssertTrue(review.contains("Zeile 2:"))
        XCTAssertTrue(review.contains("Es wird nichts installiert."))
        sheet.buttons["brewfile.review.cancel"].click()
    }

    func assertGermanImport(
        withArguments arguments: [String],
        expectedStatus expected: String,
        outputMarker marker: String?,
        cancel: Bool
    ) {
        openBrewfileReview(
            withContents: "brew 'mockwget'",
            extraArguments: germanBrewfileArguments() + arguments
        )
        app.sheets.firstMatch.buttons["brewfile.review.install"].click()
        let action = app.sheets.firstMatch.buttons["brewfile.import.action"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        if cancel {
            XCTAssertEqual(action.title, "Abbrechen")
            action.click()
        }
        let status = app.staticTexts["brewfile.import.status"]
        expectation(for: NSPredicate(format: "value == %@", expected), evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(action.title, "Schließen")
        let output = stringValue(of: app.textViews["brewfile.import.output"])
        if cancel {
            XCTAssertTrue(output.contains("MOCK_IMPORT_STARTED"))
            XCTAssertTrue(output.contains("MOCK_IMPORT_CANCELLED"))
            XCTAssertFalse(output.contains("MOCK_IMPORT_OK"))
        } else if let marker {
            XCTAssertTrue(output.contains(marker))
        }
        action.click()
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testGermanBrewfileConfirmedImport() {
        assertGermanImport(
            withArguments: [],
            expectedStatus: "Import abgeschlossen.",
            outputMarker: "MOCK_IMPORT_OK",
            cancel: false
        )
    }

    func testGermanBrewfileFailedImport() {
        assertGermanImport(
            withArguments: ["-BPMockBrewfileImportFails"],
            expectedStatus: "Import fehlgeschlagen. Weitere Informationen finden Sie in der Ausgabe.",
            outputMarker: "MOCK_IMPORT_FAILED",
            cancel: false
        )
    }

    func testGermanBrewfileCancelledImport() {
        assertGermanImport(
            withArguments: ["-BPMockHoldBrewfileImportUntilCancelled"],
            expectedStatus: "Import abgebrochen. Es können bereits Änderungen vorgenommen worden sein.",
            outputMarker: nil,
            cancel: true
        )
    }

    func openGermanMockExport(withArguments arguments: [String]) {
        launch(
            withArguments: ["-BPMockBrew", "-BPMockExportURL", "/fixture/Brewfile"]
                + germanBrewfileArguments()
                + arguments
        )
        // AppKit exposes the existing German submenu title (Tools) in the menu bar.
        app.menuBars.menuBarItems["Tools"].click()
        app.menuItems["Exportiere Brew Installation..."].click()
    }

    func testGermanBrewfileSlowAndSuccessfulExport() {
        openGermanMockExport(withArguments: ["-BPMockSlowExport"])
        let close = app.sheets.firstMatch.buttons["brewfile.export.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertEqual(close.title, "Schließen")
        XCTAssertFalse(close.isEnabled)
        XCTAssertTrue(app.descendants(matching: .any)["brewfile.export.progress"].exists)
        XCTAssertTrue(app.sheets.firstMatch.staticTexts["Bitte warten, während die Datei generiert wird."].exists)
        expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: close)
        waitForExpectations(timeout: 15)
        XCTAssertEqual(stringValue(of: app.staticTexts["brewfile.export.status"]), "Export erfolgreich")
        close.click()
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    func testGermanBrewfileFailedExport() {
        openGermanMockExport(withArguments: ["-BPMockExportFails"])
        let status = app.staticTexts["brewfile.export.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertEqual(stringValue(of: status), "Export fehlgeschlagen")
        XCTAssertTrue(stringValue(of: app.staticTexts["brewfile.export.detail"]).contains("MOCK_EXPORT_FAILED"))
        let close = app.sheets.firstMatch.buttons["brewfile.export.close"]
        XCTAssertEqual(close.title, "Schließen")
        XCTAssertTrue(close.isEnabled)
        close.click()
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    // Smoke test: the app launches and presents its main window.
    func testAppLaunchesAndShowsMainWindow() {
        launch(withArguments: [])
    }

    // Unavailable Homebrew cannot satisfy the normal helper's mockwget settle
    // wait. Only these recovery journeys use this distinct launch path.
    func launchRecovery(withArguments arguments: [String]) {
        app.launchArguments = ["-BPMockBrew", "-BPLastSelectedSidebarRow", "1", "-BPSortColumnIdentifier", ""] + arguments
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["homebrew.retry"].waitForExistence(timeout: 30))
    }

    func testMissingHomebrewShowsActionableNonmodalRecovery() {
        launchRecovery(withArguments: ["-BPMockHomebrewMissing"])
        XCTAssertTrue(app.buttons["homebrew.install"].exists)
        XCTAssertTrue(app.buttons["homebrew.retry"].isEnabled)
        XCTAssertTrue(app.staticTexts["homebrew.recovery.message"].exists)
        XCTAssertGreaterThan(app.staticTexts["homebrew.recovery.message"].frame.size.height, 30.0)
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertEqual(app.dialogs.count, 0)
        XCTAssertFalse(formulaCell(withName: "mockwget").exists)
    }

    func testPersistentHomebrewFailureRemainsRetryableWithoutDuplicateRecovery() {
        launchRecovery(withArguments: ["-BPMockHomebrewMissing", "-BPMockSlowHomebrewRetry"])
        let retry = app.buttons["homebrew.retry"]
        retry.click()
        XCTAssertFalse(retry.isEnabled)
        let enabled = NSPredicate(format: "enabled == YES")
        XCTAssertEqual(
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: enabled, object: retry)], timeout: 10),
            .completed
        )
        XCTAssertEqual(app.buttons.matching(identifier: "homebrew.retry").count, 1)
        XCTAssertEqual(app.sheets.count, 0)
        XCTAssertFalse(formulaCell(withName: "mockwget").exists)
    }

    func testHomebrewRetryRecoversInstalledPackagesWithoutRelaunching() {
        launchRecovery(withArguments: ["-BPMockHomebrewRecovers", "-BPMockSlowHomebrewRetry"])
        let retry = app.buttons["homebrew.retry"]
        retry.click()
        XCTAssertFalse(retry.isEnabled)
        XCTAssertTrue(formulaCell(withName: "mockwget").waitForExistence(timeout: 30))
        XCTAssertFalse(app.buttons["homebrew.retry"].exists)
        assertSelectedSidebarIdentifier("sidebar.formulae.installed")
        XCTAssertEqual(app.sheets.count, 0)
    }

    // MARK: - Sidebar navigation journeys

    // Notification launch journeys start somewhere other than Installed, so they
    // cannot use the shared helper's Installed-list settle wait.
    func launch(withPendingNotificationTarget target: String) {
        app.launchArguments = [
            "-BPMockBrew",
            "-BPMockHoldCatalogUntilReleased",
            "-BPMockNotificationTarget",
            target,
            "-BPLastSelectedSidebarRow",
            "1",
            "-BPSortColumnIdentifier",
            ""
        ]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 30.0))
        XCTAssertTrue(
            app.buttons["Stop Reloading"].waitForExistence(timeout: 30.0),
            "the journey must observe the initial reload before its completion"
        )
    }

    func assertSelectedSidebarIdentifier(_ identifier: String) {
        let row = app.outlines.firstMatch.outlineRows
            .containing(.staticText, identifier: identifier)
            .firstMatch
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES AND selected == YES"),
            object: row
        )
        let result = XCTWaiter.wait(for: [selected], timeout: 30.0)
        if result != .completed {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertEqual(result, .completed, "\(identifier) should be the selected sidebar destination")
    }

    func waitForNotificationLaunchReloadToFinish() {
        let finished = NSPredicate(format: "exists == NO")
        expectation(for: finished, evaluatedWith: app.buttons["Stop Reloading"])
        waitForExpectations(timeout: 30.0)
    }

    func assertPendingNotificationTarget(
        _ target: String,
        selectsSidebar identifier: String,
        fixtureName: String
    ) {
        launch(withPendingNotificationTarget: target)
        assertSelectedSidebarIdentifier(identifier)
        XCTAssertTrue(app.buttons["Stop Reloading"].exists, "selection must be observed before normal completion")
        clickNotificationTestMenuItem("mock.catalog.complete")
        waitForNotificationLaunchReloadToFinish()
        assertSelectedSidebarIdentifier(identifier)
        XCTAssertTrue(
            formulaCell(withName: fixtureName).waitForExistence(timeout: 15.0),
            "the notification destination should display its outdated package"
        )
        XCTAssertFalse(
            formulaCell(withName: "mockwget").exists,
            "an outdated notification must not leave the Installed formulae list selected"
        )
        XCTAssertFalse(
            formulaCell(withName: "mockvscode").exists,
            "cask notifications must select Outdated, not Installed Casks"
        )
    }

    func testPendingFormulaeNotificationSurvivesInitialReload() {
        assertPendingNotificationTarget(
            "formulae",
            selectsSidebar: "sidebar.formulae.outdated",
            fixtureName: "mockgit"
        )
    }

    func testPendingCaskNotificationSurvivesInitialReload() {
        assertPendingNotificationTarget(
            "casks",
            selectsSidebar: "sidebar.casks.outdated",
            fixtureName: "mockchrome"
        )
    }

    func testPendingMixedNotificationOpensFormulaeAndSurvivesInitialReload() {
        assertPendingNotificationTarget(
            "mixed",
            selectsSidebar: "sidebar.tools.updates",
            fixtureName: "mockgit"
        )
    }

    func testPendingNotificationDoesNotReplayAfterUserNavigatesDuringReload() {
        launch(withPendingNotificationTarget: "casks")
        assertSelectedSidebarIdentifier("sidebar.casks.outdated")
        XCTAssertTrue(app.buttons["Stop Reloading"].exists, "navigation must start while the reload is held")
        sidebarRow("sidebar.formulae.installed").click()
        assertSelectedSidebarIdentifier("sidebar.formulae.installed")
        XCTAssertTrue(app.buttons["Stop Reloading"].exists, "user navigation must precede normal completion")
        clickNotificationTestMenuItem("mock.catalog.complete")
        waitForNotificationLaunchReloadToFinish()
        assertSelectedSidebarIdentifier("sidebar.formulae.installed")
        XCTAssertTrue(
            formulaCell(withName: "mockwget").waitForExistence(timeout: 15.0),
            "finishing the reload must keep the user's later navigation"
        )
        XCTAssertFalse(formulaCell(withName: "mockchrome").exists)
    }

    // The mock-only menu drives real controller actions without typing into a
    // non-key window on CI. It carries semantic payloads, never sidebar row logic.
    func clickNotificationTestMenuItem(_ title: String) {
        app.menuBars.menuBarItems["Notification Test"].click()
        app.menuItems[title].click()
    }

    func assertWarmNotificationTarget(
        _ target: String,
        selectsSidebar identifier: String,
        fixtureName: String,
        alreadySelected: Bool,
        pendingSearch: Bool
    ) {
        launch(withArguments: ["-BPMockBrew", "-BPMockWarmNotificationTarget", target])
        waitForNotificationLaunchReloadToFinish()
        if alreadySelected {
            sidebarRow(identifier).click()
            assertSelectedSidebarIdentifier(identifier)
            XCTAssertTrue(formulaCell(withName: fixtureName).waitForExistence(timeout: 15.0))
        }

        if pendingSearch {
            // Queue the 150 ms debounce and route the notification in the same event.
            clickNotificationTestMenuItem("Search Then Open Mock Notification")
            let noLateSearch = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == YES"),
                object: formulaCell(withName: "mockvscode")
            )
            noLateSearch.isInverted = true
            XCTAssertEqual(
                XCTWaiter.wait(for: [noLateSearch], timeout: 1.0),
                .completed,
                "a pending debounce must not restart search after notification navigation"
            )
        } else {
            clickNotificationTestMenuItem("Search Mock Packages")
            XCTAssertTrue(
                formulaCell(withName: "mockvscode").waitForExistence(timeout: 15.0),
                "the journey must observe real search results before routing the notification"
            )
            XCTAssertEqual(stringValue(of: app.searchFields.firstMatch), "mockvscode")
            clickNotificationTestMenuItem("Open Mock Notification")
        }

        assertSelectedSidebarIdentifier(identifier)
        XCTAssertEqual(
            stringValue(of: app.searchFields.firstMatch),
            "",
            "notification navigation should clear the search field"
        )
        let appeared = formulaCell(withName: fixtureName).waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the outdated destination must remain visible after leaving search")
        XCTAssertFalse(
            formulaCell(withName: "mockvscode").exists,
            "the table should show the outdated destination, not stale search results"
        )
        XCTAssertFalse(formulaCell(withName: "mockwget").exists)
    }

    func testFormulaeNotificationLeavesSearchForOutdatedDestination() {
        assertWarmNotificationTarget(
            "formulae",
            selectsSidebar: "sidebar.formulae.outdated",
            fixtureName: "mockgit",
            alreadySelected: false,
            pendingSearch: false
        )
    }

    func testCaskNotificationLeavesSearchForOutdatedDestination() {
        assertWarmNotificationTarget(
            "casks",
            selectsSidebar: "sidebar.casks.outdated",
            fixtureName: "mockchrome",
            alreadySelected: false,
            pendingSearch: false
        )
    }

    func testFormulaeNotificationLeavesSearchOnAlreadySelectedDestination() {
        assertWarmNotificationTarget(
            "formulae",
            selectsSidebar: "sidebar.formulae.outdated",
            fixtureName: "mockgit",
            alreadySelected: true,
            pendingSearch: false
        )
    }

    func testCaskNotificationLeavesSearchOnAlreadySelectedDestination() {
        assertWarmNotificationTarget(
            "casks",
            selectsSidebar: "sidebar.casks.outdated",
            fixtureName: "mockchrome",
            alreadySelected: true,
            pendingSearch: false
        )
    }

    func testFormulaeNotificationCancelsPendingSearch() {
        assertWarmNotificationTarget(
            "formulae",
            selectsSidebar: "sidebar.formulae.outdated",
            fixtureName: "mockgit",
            alreadySelected: false,
            pendingSearch: true
        )
    }

    func testCaskNotificationCancelsPendingSearch() {
        assertWarmNotificationTarget(
            "casks",
            selectsSidebar: "sidebar.casks.outdated",
            fixtureName: "mockchrome",
            alreadySelected: false,
            pendingSearch: true
        )
    }

    // Journey: the sidebar presents every navigation destination.
    // Runs with the mock: a real-brew launch spawns a full `brew` reload whose
    // subprocesses outlive the test when the app is terminated, and the orphaned
    // work has caused timeouts in whichever mock test runs next on CI.
    func testSidebarShowsAllNavigationItems() {
        launch(withArguments: ["-BPMockBrew"])
        let outline = sidebar()
        // By identifier, so both "Installed" rows and both "Outdated" rows are
        // asserted rather than one standing in for the other.
        let items = [
            "sidebar.formulae.installed",
            "sidebar.formulae.outdated",
            "sidebar.formulae.all",
            "sidebar.formulae.leaves",
            "sidebar.formulae.pinned",
            "sidebar.formulae.repositories",
            "sidebar.casks.installed",
            "sidebar.casks.outdated",
            "sidebar.casks.all",
            "sidebar.tools.doctor",
            "sidebar.tools.update",
            "sidebar.tools.services",
            "sidebar.tools.updates"
        ]
        for item in items {
            XCTAssertTrue(
                outline.staticTexts[item].waitForExistence(timeout: 15.0),
                "the sidebar should show the \(item) row"
            )
        }
    }

    // Journey: selecting a Tools item switches the content to that tool's view.
    // Mock-launched for the same reason as testSidebarShowsAllNavigationItems.
    func testNavigatingToToolViewsFromSidebar() {
        launch(withArguments: ["-BPMockBrew"])

        let doctorItem = sidebarRow("sidebar.tools.doctor")
        XCTAssertTrue(doctorItem.waitForExistence(timeout: 15.0), "Doctor item should exist")
        doctorItem.click()
        XCTAssertTrue(
            app.staticTexts["Homebrew Doctor"].waitForExistence(timeout: 15.0),
            "selecting Doctor should show the Homebrew Doctor view"
        )

        let updateItem = sidebarRow("sidebar.tools.update")
        XCTAssertTrue(updateItem.waitForExistence(timeout: 15.0), "Update item should exist")
        updateItem.click()
        XCTAssertTrue(
            app.staticTexts["Homebrew Updater"].waitForExistence(timeout: 15.0),
            "selecting Update should show the Homebrew Updater view"
        )
    }

    // MARK: - Mock-brew data journeys

    // Formula names render as NSTextField cells in the table, so the displayed name
    // is the element's value rather than its label — match on value.
    func formulaCell(withName name: String) -> XCUIElement {
        // BEGINSWITH (not ==) so a pinned formula's cell — whose value/label is the
        // name followed by the pin symbol — still matches across AppKit and SwiftUI tables.
        let predicate = NSPredicate(
            format: "(elementType == %lu OR elementType == %lu) AND (value BEGINSWITH %@ OR label BEGINSWITH %@) AND NOT (identifier BEGINSWITH 'formula.')",
            XCUIElement.ElementType.textField.rawValue,
            XCUIElement.ElementType.staticText.rawValue,
            name,
            name
        )
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    // Journey: launched with the mock brew interface, the Installed list populates
    // with the fixture formulae instead of whatever is on the host.
    func testInstalledListShowsMockFormulae() {
        launch(withArguments: ["-BPMockBrew"])

        XCTAssertTrue(
            formulaCell(withName: "mockwget").waitForExistence(timeout: 30.0),
            "the mock installed list should populate the formula table"
        )
        XCTAssertTrue(
            formulaCell(withName: "mockgit").waitForExistence(timeout: 15.0),
            "the mock installed list should include mockgit"
        )
    }

    // Journey: selecting a not-installed formula offers Install in the toolbar.
    func testNotInstalledFormulaOffersInstall() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.formulae.all").click()
        let htop = formulaCell(withName: "mockhtop")
        let htopAppeared = htop.waitForExistence(timeout: 30.0)
        if !htopAppeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(htopAppeared, "mockhtop should be listed under All Formulae")
        htop.click()

        let installButton = app.buttons["Install Formula"]
        let appeared = installButton.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "selecting a not-installed formula should offer Install in the toolbar")
    }

    // Journey: clicking Install on a not-installed formula asks for confirmation.
    func testInstallPresentsConfirmationDialog() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.formulae.all").click()
        let htop = formulaCell(withName: "mockhtop")
        XCTAssertTrue(htop.waitForExistence(timeout: 30.0), "mockhtop should be listed under All Formulae")
        htop.click()

        let installButton = app.buttons["Install Formula"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 15.0), "Install should be offered")
        installButton.click()

        // installFormula: presents a Yes / Cancel confirmation.
        let yesButton = app.buttons["Yes"]
        let confirmationAppeared = yesButton.waitForExistence(timeout: 15.0)
        if !confirmationAppeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(confirmationAppeared, "clicking Install should present a Yes/Cancel confirmation")

        // Cancel so the test doesn't proceed into the install operation.
        dismissConfirmationSheet()
    }

    // Journey: selecting an installed formula offers Uninstall in the toolbar.
    func testInstalledFormulaOffersUninstall() {
        launch(withArguments: ["-BPMockBrew"])

        // The Installed list is selected by default; mockwget is installed.
        let wget = formulaCell(withName: "mockwget")
        XCTAssertTrue(wget.waitForExistence(timeout: 30.0), "mockwget should be in the Installed list")
        wget.click()

        let uninstallButton = app.buttons["Uninstall Formula"]
        let appeared = uninstallButton.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "selecting an installed formula should offer Uninstall in the toolbar")
    }

    // Journey: the Formula menu exposes Pin / Unpin items (bindings load without
    // crashing). Presence — not enabled state — is asserted: disabled menu items
    // still exist in the tree, so this guards the xib wiring regardless of selection.
    func testFormulaMenuExposesPinAndUnpin() {
        launch(withArguments: ["-BPMockBrew"])

        // Select an installed formula so the pin items apply to a real selection.
        let wget = formulaCell(withName: "mockwget")
        XCTAssertTrue(wget.waitForExistence(timeout: 30.0), "mockwget should be in the Installed list")
        wget.click()

        app.menuBars.menuBarItems["Formula"].click()

        let pinItem = app.menuItems["Pin Formula"]
        let pinAppeared = pinItem.waitForExistence(timeout: 10.0)
        if !pinAppeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(pinAppeared, "Formula menu should contain a Pin Formula item")
        XCTAssertTrue(app.menuItems["Unpin Formula"].exists, "Formula menu should contain an Unpin Formula item")

        app.typeKey(.escape, modifierFlags: [])
    }

    // Journey: selecting a formula shows the "Required by" (dependents) row in the
    // detail pane. Guards that the SwiftUI inspector renders both metadata and
    // asynchronous dependents.
    func testDetailPaneShowsRequiredByRow() {
        launch(withArguments: ["-BPMockBrew"])

        let wget = formulaCell(withName: "mockwget")
        XCTAssertTrue(wget.waitForExistence(timeout: 30.0), "mockwget should be in the Installed list")
        wget.click()

        let requiredByLabel = app.staticTexts["Required by:"]
        let appeared = requiredByLabel.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the detail pane should show the Required by row")

        let requiredByValue = app.descendants(matching: .any)
            .matching(identifier: "formula.detail.requiredBy")
            .firstMatch
        XCTAssertTrue(requiredByValue.waitForExistence(timeout: 15.0))
        let requiredByContent = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "mockcurl",
            "mockcurl"
        )
        expectation(for: requiredByContent, evaluatedWith: requiredByValue)
        waitForExpectations(timeout: 10.0)
    }

    // Journey: selecting a pinned formula shows the "Pinned" row in the detail pane.
    // The mock reports mockgit as pinned (its `brew list --pinned` fixture).
    func testDetailPaneShowsPinnedRowForPinnedFormula() {
        launch(withArguments: ["-BPMockBrew"])

        let git = formulaCell(withName: "mockgit")
        XCTAssertTrue(git.waitForExistence(timeout: 30.0), "mockgit should be in the Installed list")
        git.click()

        // The row is hidden unless the formula is pinned, so its presence in the
        // accessibility tree confirms both the xib row and the isFormulaPinned wiring.
        let pinnedLabel = app.staticTexts["Pinned:"]
        let appeared = pinnedLabel.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the detail pane should show the Pinned row for a pinned formula")
    }

    // Journey: the Pinned sidebar section lists only pinned formulae.
    func testPinnedSidebarSectionListsPinnedFormulae() {
        launch(withArguments: ["-BPMockBrew"])

        // The mock pins mockgit (its `brew list --pinned` fixture).
        sidebarRow("sidebar.formulae.pinned").click()

        let git = formulaCell(withName: "mockgit")
        let appeared = git.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the Pinned section should list mockgit")
        XCTAssertFalse(
            formulaCell(withName: "mockwget").exists,
            "unpinned formulae should not appear in the Pinned section"
        )
    }

    // Journey: the Casks section lists installed casks (browse-only for now).
    func testCasksSidebarSectionListsInstalledCasks() {
        launch(withArguments: ["-BPMockBrew"])

        let installedCasks = sidebarRow("sidebar.casks.installed")
        XCTAssertTrue(installedCasks.waitForExistence(timeout: 30.0), "sidebar should load")
        installedCasks.click()

        let chrome = formulaCell(withName: "mockchrome")
        let appeared = chrome.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the Casks section should list mockchrome")
        XCTAssertTrue(formulaCell(withName: "mockvscode").exists, "the Casks section should list mockvscode")
        XCTAssertFalse(
            formulaCell(withName: "mockwget").exists,
            "formulae should not appear in the Casks section"
        )
    }

    // Journey: the Outdated casks section lists the outdated cask and offers
    // Update, which asks for confirmation (dispatches to `upgrade --cask`).
    func testOutdatedCaskOffersUpdateWithConfirmation() {
        launch(withArguments: ["-BPMockBrew"])

        let outdatedCasks = sidebarRow("sidebar.casks.outdated")
        XCTAssertTrue(outdatedCasks.waitForExistence(timeout: 30.0), "sidebar should load")
        outdatedCasks.click()

        let chrome = formulaCell(withName: "mockchrome")
        let appeared = chrome.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the outdated cask should be listed")
        chrome.click()

        let updateButton = app.buttons["Update Formula"]
        XCTAssertTrue(
            updateButton.waitForExistence(timeout: 15.0),
            "selecting an outdated cask should offer Update in the toolbar"
        )
        updateButton.click()

        let yesButton = app.buttons["Yes"]
        XCTAssertTrue(
            yesButton.waitForExistence(timeout: 15.0),
            "clicking Update on a cask should present a Yes/Cancel confirmation"
        )

        // Cancel so the test doesn't proceed into the operation.
        dismissConfirmationSheet()
    }

    /// Waits for the sidebar to reach the collapsed (or expanded) state.
    ///
    /// Measured by width rather than -isHittable: the CI runner's window is never
    /// key, so hit testing reports false regardless of whether the sidebar is
    /// showing. A collapsed NSSplitViewItem either drops out of the tree or reports
    /// zero width.
    func waitForSidebar(_ sidebar: XCUIElement, collapsed: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date(timeIntervalSinceNow: timeout)
        while deadline.timeIntervalSinceNow > 0 {
            let isCollapsed = !sidebar.exists || sidebar.frame.size.width < 1.0
            if isCollapsed == collapsed {
                return true
            }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return false
    }

    // Journey: the About window credits only code the app actually ships.
    //
    // Sparkle was removed from Cakebrew but stayed in Credits.rtf for years —
    // shipping an attribution for code that isn't there is a licensing-accuracy
    // problem, not just a stale string.
    func testAboutWindowCreditsOnlyShippedCode() {
        launch(withArguments: ["-BPMockBrew"])

        app.menuBars.menuBarItems["Cakebrew"].click()
        let aboutItem = app.menuItems["About Cakebrew"]
        XCTAssertTrue(aboutItem.waitForExistence(timeout: 10.0), "the app menu should offer About")
        aboutItem.click()

        let credits = NSPredicate(format: "value CONTAINS %@", "DCOAboutWindowController")
        let creditsView = app.textViews.matching(credits).firstMatch
        let appeared = creditsView.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the About window should render the credits")

        let shown = stringValue(of: creditsView)
        XCTAssertFalse(
            shown.contains("Sparkle"),
            "Sparkle is not shipped and must not be credited"
        )
        XCTAssertFalse(
            shown.contains("PXSourceList"),
            "PXSourceList is not shipped either"
        )
    }

    // Journey: the app reopens on the sidebar row last used, rather than always on
    // Installed. The stored row arrives through the argument domain here, which is
    // what -[BPPreferences lastSelectedSidebarRow] reads.
    func testReopensOnTheLastUsedSidebarRow() {
        launch(withArguments: ["-BPMockBrew", "-BPLastSelectedSidebarRow", "12"])

        // Row 12 is Doctor, so its view should be showing without any navigation.
        XCTAssertTrue(
            app.staticTexts["Homebrew Doctor"].waitForExistence(timeout: 30.0),
            "the app should reopen on the row the user last selected"
        )
    }

    // Journey: a stored row that no longer addresses a real destination falls back
    // to Installed rather than opening on nothing.
    func testAnOutOfRangeStoredRowFallsBackToInstalled() {
        // Row 99 addresses nothing, so the app should land on Installed — which is
        // exactly what the shared launch helper waits for.
        launch(withArguments: ["-BPMockBrew", "-BPLastSelectedSidebarRow", "99"])

        XCTAssertTrue(
            formulaCell(withName: "mockwget").waitForExistence(timeout: 30.0),
            "an unusable stored row should fall back to the Installed list"
        )
    }

    // Journey: uninstalling a cask offers to remove its support files too, and
    // uninstalling a formula does not — formulae have no zap stanza.
    func testZapCheckboxAppearsForCasksOnly() {
        launch(withArguments: ["-BPMockBrew"])

        // A cask: the box should be offered.
        sidebarRow("sidebar.casks.installed").click()
        let cask = formulaCell(withName: "mockchrome")
        XCTAssertTrue(cask.waitForExistence(timeout: 30.0), "mockchrome should be an installed cask")
        cask.click()

        let uninstall = app.buttons["Uninstall Formula"]
        XCTAssertTrue(uninstall.waitForExistence(timeout: 15.0))
        uninstall.click()

        let zap = NSPredicate(format: "title CONTAINS %@", "zap")
        let zapBox = app.checkBoxes.matching(zap).firstMatch
        let offered = zapBox.waitForExistence(timeout: 15.0)
        if !offered {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(offered, "a cask uninstall should offer to remove support files")
        dismissConfirmationSheet()

        // A formula: it should not be.
        sidebarRow("sidebar.formulae.installed").click()
        let formula = formulaCell(withName: "mockwget")
        XCTAssertTrue(formula.waitForExistence(timeout: 30.0))
        formula.click()

        let uninstallFormula = app.buttons["Uninstall Formula"]
        XCTAssertTrue(uninstallFormula.waitForExistence(timeout: 15.0))
        uninstallFormula.click()
        XCTAssertTrue(app.buttons["Yes"].waitForExistence(timeout: 15.0), "the confirmation should appear")
        XCTAssertFalse(
            app.checkBoxes.matching(zap).firstMatch.exists,
            "formulae have no zap stanza, so the box must not be offered"
        )
        dismissConfirmationSheet()
    }

    // Journey: confirming an install actually runs it against the mock.
    //
    // Every other mutating journey stops at Cancel, which is why the missing mock
    // overrides went unnoticed — the operations they guarded were never reached.
    // This one goes through, so it fails if the mock ever stops covering install.
    func testConfirmingAnInstallRunsAgainstTheMock() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.formulae.all").click()
        let htop = formulaCell(withName: "mockhtop")
        XCTAssertTrue(htop.waitForExistence(timeout: 30.0), "mockhtop should be listed under All Formulae")
        htop.click()

        let installButton = app.buttons["Install Formula"]
        XCTAssertTrue(installButton.waitForExistence(timeout: 15.0))
        installButton.click()

        // Scoped to the sheet, not the app. An alert's buttons are mirrored to the
        // Touch Bar, so an app-wide query matches twice — and firstMatch can pick
        // the Touch Bar element, which is not clickable.
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 15.0), "the confirmation should appear")
        sheet.buttons["Yes"].click()

        // The marker proves the mock served this, not real brew.
        let streamed = NSPredicate(format: "value CONTAINS %@", "MOCK_INSTALL_OK")
        let output = app.textViews.matching(streamed).firstMatch
        let appeared = output.waitForExistence(timeout: 20.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the operation window should stream the mock's install output")
    }

    func testClearingQueuedSearchKeepsInstalledFormulaeVisible() {
        launch(withArguments: ["-BPMockBrew", "-BPMockWarmNotificationTarget", "casks"])
        waitForNotificationLaunchReloadToFinish()
        assertSelectedSidebarIdentifier("sidebar.formulae.installed")
        XCTAssertTrue(formulaCell(withName: "mockwget").exists)
        XCTAssertTrue(formulaCell(withName: "mockgit").exists)
        XCTAssertFalse(formulaCell(withName: "mockvscode").exists)

        // Queue and clear within one main event, before the 150 ms debounce fires.
        // The mock menu drives the toolbar text-change path without keyboard focus.
        clickNotificationTestMenuItem("Search Then Clear Mock Search")
        XCTAssertEqual(stringValue(of: app.searchFields.firstMatch), "")
        let noLateSearch = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == YES"),
            object: formulaCell(withName: "mockvscode")
        )
        noLateSearch.isInverted = true
        let result = XCTWaiter.wait(for: [noLateSearch], timeout: 1.0)
        if result != .completed {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertEqual(
            result,
            .completed,
            "clearing before debounce must not display late search results"
        )
        assertSelectedSidebarIdentifier("sidebar.formulae.installed")
        XCTAssertEqual(stringValue(of: app.searchFields.firstMatch), "")
        XCTAssertTrue(formulaCell(withName: "mockwget").exists)
        XCTAssertTrue(formulaCell(withName: "mockgit").exists)
        XCTAssertFalse(formulaCell(withName: "mockvscode").exists)
    }

    // Journey: searching finds casks, and does not move the user out of the list
    // they were browsing.
    //
    // Search used to walk only allFormulae, so a cask token returned nothing, and
    // it force-selected Formulae ▸ All — so someone browsing All Casks who typed
    // three characters landed in the formula namespace looking at an empty table.
    func testSearchingFindsCasksAndKeepsTheSidebarSelection() {
        launch(withArguments: ["-BPMockBrew", "-BPMockWarmNotificationTarget", "casks"])
        waitForNotificationLaunchReloadToFinish()
        let outline = sidebar()

        sidebarRow("sidebar.casks.all").click()
        XCTAssertTrue(
            formulaCell(withName: "mockchrome").waitForExistence(timeout: 30.0),
            "All Casks should list the mock casks"
        )
        let rowBefore = selectedSidebarRow(outline)

        // The existing mock menu drives the same search entry point without typing,
        // which needs a key window unavailable on CI.
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 15.0), "the toolbar should offer a search field")
        clickNotificationTestMenuItem("Search Mock Packages")
        // mockvscode was already in All Casks. Wait for a nonmatching cask to
        // disappear so that observing it now proves the debounced search finished.
        XCTAssertTrue(formulaCell(withName: "mockchrome").waitForNonExistence(timeout: 15.0))
        XCTAssertTrue(
            formulaCell(withName: "mockvscode").waitForExistence(timeout: 15.0),
            "the search must return the matching cask"
        )
        XCTAssertEqual(stringValue(of: searchField), "mockvscode")
        XCTAssertFalse(formulaCell(withName: "mockchrome").exists)
        XCTAssertFalse(formulaCell(withName: "mockwget").exists)
        assertSelectedSidebarIdentifier("sidebar.casks.all")

        XCTAssertEqual(
            selectedSidebarRow(outline),
            rowBefore,
            "searching casks should preserve the sidebar selection"
        )
    }

    /// Index of the selected sidebar row, or -1.
    func selectedSidebarRow(_ sidebar: XCUIElement) -> Int {
        let rows = sidebar.outlineRows.allElementsBoundByIndex
        for (idx, row) in rows.enumerated() where row.isSelected {
            return idx
        }
        return -1
    }

    // Journey: an empty list explains itself rather than showing column headers
    // over blank space.
    //
    // Outdated being empty is the happy path, and it used to look identical to a
    // list that had failed to load.
    func testAnEmptyListShowsAnExplanation() {
        launch(withArguments: ["-BPMockBrew", "-BPMockEmptyOutdated"])

        sidebarRow("sidebar.formulae.outdated").click()

        let explanation = app.staticTexts["Everything Is Up to Date"]
        let appeared = explanation.waitForExistence(timeout: 20.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "an empty Outdated list should say so")
    }

    // Journey: View ▸ Show/Hide Sidebar collapses the sidebar and restores it.
    // There was no way to hide the sidebar at all before — no menu item, no
    // shortcut, no toolbar button — despite the window using a collapsible
    // NSSplitViewItem.
    func testShowHideSidebarCollapsesAndRestoresTheSidebar() {
        launch(withArguments: ["-BPMockBrew"])
        let outline = sidebar()
        // Width, not isHittable: the CI runner's window is never key, so hit
        // testing reports false there even while the sidebar is plainly visible.
        XCTAssertGreaterThan(outline.frame.size.width, 1.0, "the sidebar starts visible")

        // AppKit retitles the item to "Hide Sidebar" or "Show Sidebar" to match the
        // current state, so match on the noun rather than a fixed title.
        let sidebarItem = NSPredicate(format: "title ENDSWITH %@", "Sidebar")
        app.menuBars.menuBarItems["View"].click()
        let toggleItem = app.menuItems.matching(sidebarItem).firstMatch
        XCTAssertTrue(toggleItem.waitForExistence(timeout: 10.0), "View should offer a sidebar toggle")
        toggleItem.click()

        let didCollapse = waitForSidebar(outline, collapsed: true, timeout: 15.0)
        if !didCollapse {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(didCollapse, "the sidebar should collapse")

        // And back again — it is a toggle, not a one-way hide.
        app.menuBars.menuBarItems["View"].click()
        app.menuItems.matching(sidebarItem).firstMatch.click()

        XCTAssertTrue(
            waitForSidebar(outline, collapsed: false, timeout: 15.0),
            "the sidebar should come back"
        )
    }

    func testSettingsWindowOpensFromMenu() {
        launch(withArguments: ["-BPMockBrew"])

        app.menuBars.menuBarItems["Cakebrew"].click()
        // AppKit auto-renames "Preferences…" to "Settings…" (macOS 13+), so the
        // rendered item carries the new title on every supported OS.
        let prefsItem = app.menuItems["Settings…"]
        XCTAssertTrue(prefsItem.waitForExistence(timeout: 10.0), "the app menu should show Settings…")
        prefsItem.click()

        let prefsWindow = app.windows["Settings"]
        let appeared = prefsWindow.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the Preferences window should open")

        XCTAssertTrue(
            prefsWindow.checkBoxes["Check for outdated packages in the background"].exists,
            "the background-check toggle should be present"
        )
        XCTAssertTrue(
            prefsWindow.checkBoxes["Include auto-updating apps in outdated casks"].exists,
            "the greedy-casks toggle should be present"
        )

        // Helper status row. Unsandboxed (the shipping configuration), so it must
        // say the helper isn't needed rather than nagging for approval.
        XCTAssertTrue(
            prefsWindow.staticTexts["Homebrew access:"].exists,
            "the helper status row should be present"
        )
        let notRequired = NSPredicate(format: "value CONTAINS %@", "Not required")
        XCTAssertTrue(
            prefsWindow.staticTexts.matching(notRequired).firstMatch.exists,
            "an unsandboxed build reports the helper as not required"
        )

        prefsWindow.buttons[XCUIIdentifierCloseWindow].click()
    }

    // Journey: the Services tool lists brew services with status and offers
    // the start/stop/restart controls.
    func testServicesToolListsServicesWithControls() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.tools.services").click()

        XCTAssertTrue(
            app.staticTexts["Homebrew Services"].waitForExistence(timeout: 15.0),
            "selecting Services should show the Services view"
        )

        let postgres = formulaCell(withName: "mockpostgres")
        let appeared = postgres.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the services table should list mockpostgres")
        XCTAssertTrue(formulaCell(withName: "mockredis").exists, "the services table should list mockredis")

        XCTAssertTrue(app.buttons["Start"].exists, "a Start button should be present")
        XCTAssertTrue(app.buttons["Stop"].exists, "a Stop button should be present")
        XCTAssertTrue(app.buttons["Restart"].exists, "a Restart button should be present")

        // Selecting the running service enables Stop.
        postgres.click()
        XCTAssertTrue(app.buttons["Stop"].waitForExistence(timeout: 5.0))
        XCTAssertTrue(app.buttons["Stop"].isEnabled, "Stop should enable for a started service")
    }

    func waitForServiceDetails(containing text: String) {
        let details = app.textViews["services.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 10))
        let contains = NSPredicate(format: "value CONTAINS %@", text)
        let exp = XCTNSPredicateExpectation(predicate: contains, object: details)
        XCTAssertEqual(
            XCTWaiter.wait(for: [exp], timeout: 10),
            .completed,
            "CAKEBREW_UI_TREE_SERVICE_DETAILS\n\(app.debugDescription)"
        )
    }

    func testServiceDetailsFollowRunningAndStoppedSelection() {
        launch(withArguments: ["-BPMockBrew"])
        sidebarRow("sidebar.tools.services").click()
        let postgres = formulaCell(withName: "mockpostgres")
        XCTAssertTrue(postgres.waitForExistence(timeout: 15))
        postgres.click()
        waitForServiceDetails(containing: "PID: 123    User: mockuser")
        XCTAssertTrue(app.buttons["services.copyOutput"].isEnabled)
        XCTAssertFalse(app.buttons["services.openLogs"].isEnabled)
        XCTAssertFalse(app.buttons["services.revealFile"].isEnabled)
        formulaCell(withName: "mockredis").click()
        waitForServiceDetails(containing: "Service: mockredis")
        waitForServiceDetails(containing: "PID: Not available")
        XCTAssertTrue(formulaCell(withName: "mockpostgres").exists)
    }

    func testServiceDetailFailureKeepsListAndRawDiagnostic() {
        launch(withArguments: ["-BPMockBrew", "-BPMockServiceDetailsFailure"])
        sidebarRow("sidebar.tools.services").click()
        let postgres = formulaCell(withName: "mockpostgres")
        XCTAssertTrue(postgres.waitForExistence(timeout: 15))
        postgres.click()
        waitForServiceDetails(containing: "Error: mock service details unavailable")
        waitForServiceDetails(containing: "The mock service list is still available.")
        let details = stringValue(of: app.textViews["services.details"])
        XCTAssertTrue(
            details.hasPrefix("Could not load service details. Homebrew reported:\nError: mock service details unavailable"),
            "Failure and diagnostic must appear first without scrolling past metadata placeholders."
        )
        XCTAssertTrue(formulaCell(withName: "mockpostgres").exists)
        XCTAssertTrue(formulaCell(withName: "mockredis").exists)
        XCTAssertTrue(app.buttons["services.copyOutput"].isEnabled)
        XCTAssertFalse(app.buttons["services.openLogs"].isEnabled)
        XCTAssertTrue(app.buttons["Stop"].isEnabled)
    }

    // Journey: selecting a cask shows the detail pane populated from
    // `brew info --cask` (description parsed from the cask output shape).
    func testSelectingCaskShowsCaskInfoInDetailPane() {
        launch(withArguments: ["-BPMockBrew"])

        let installedCasks = sidebarRow("sidebar.casks.installed")
        XCTAssertTrue(installedCasks.waitForExistence(timeout: 30.0), "sidebar should load")
        installedCasks.click()

        let chrome = formulaCell(withName: "mockchrome")
        XCTAssertTrue(chrome.waitForExistence(timeout: 15.0), "mockchrome should be listed")
        chrome.click()

        // The mock's cask-info fixture description, parsed through the cask branch.
        let predicate = NSPredicate(
            format: "value CONTAINS %@",
            "A mock cask used for Cakebrew UI tests."
        )
        let description = app.staticTexts.matching(predicate).firstMatch
        let appeared = description.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the detail pane should show the cask description")
    }

    // Journey: the All Casks section lists the catalog; a not-installed cask
    // offers Install with confirmation (dispatches to `install --cask`).
    func testAllCasksOffersInstallWithConfirmation() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.casks.all").click()

        let firefox = formulaCell(withName: "mockfirefox")
        let appeared = firefox.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "mockfirefox should be listed under All Casks")
        firefox.click()

        let installButton = app.buttons["Install Formula"]
        XCTAssertTrue(
            installButton.waitForExistence(timeout: 15.0),
            "selecting a not-installed cask should offer Install in the toolbar"
        )
        installButton.click()

        let yesButton = app.buttons["Yes"]
        XCTAssertTrue(
            yesButton.waitForExistence(timeout: 15.0),
            "clicking Install on a cask should present a Yes/Cancel confirmation"
        )

        // Cancel so the test doesn't proceed into the operation.
        dismissConfirmationSheet()
    }

    // Journey: selecting an installed cask offers Uninstall, which asks for
    // confirmation (the operation pipeline dispatches to `uninstall --cask`).
    func testCaskOffersUninstallWithConfirmation() {
        launch(withArguments: ["-BPMockBrew"])

        let installedCasks = sidebarRow("sidebar.casks.installed")
        XCTAssertTrue(installedCasks.waitForExistence(timeout: 30.0), "sidebar should load")
        installedCasks.click()

        let chrome = formulaCell(withName: "mockchrome")
        XCTAssertTrue(chrome.waitForExistence(timeout: 15.0), "mockchrome should be listed")
        chrome.click()

        let uninstallButton = app.buttons["Uninstall Formula"]
        let appeared = uninstallButton.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "selecting a cask should offer Uninstall in the toolbar")
        uninstallButton.click()

        let yesButton = app.buttons["Yes"]
        XCTAssertTrue(
            yesButton.waitForExistence(timeout: 15.0),
            "clicking Uninstall on a cask should present a Yes/Cancel confirmation"
        )

        // Cancel so the test doesn't proceed into the operation.
        dismissConfirmationSheet()
    }

    // Journey: clicking Uninstall on an installed formula asks for confirmation.
    func testUninstallPresentsConfirmationDialog() {
        launch(withArguments: ["-BPMockBrew"])

        let wget = formulaCell(withName: "mockwget")
        XCTAssertTrue(wget.waitForExistence(timeout: 30.0), "mockwget should be in the Installed list")
        wget.click()

        let uninstallButton = app.buttons["Uninstall Formula"]
        XCTAssertTrue(uninstallButton.waitForExistence(timeout: 15.0), "Uninstall should be offered")
        uninstallButton.click()

        // uninstallFormula: presents a Yes / Cancel confirmation sheet.
        let yesButton = app.buttons["Yes"]
        let confirmationAppeared = yesButton.waitForExistence(timeout: 15.0)
        if !confirmationAppeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(confirmationAppeared, "clicking Uninstall should present a Yes/Cancel confirmation")

        // Cancel so the test doesn't proceed into the uninstall operation.
        dismissConfirmationSheet()
    }

    // Journey: selecting an outdated formula offers Update in the toolbar.
    func testOutdatedFormulaOffersUpdate() {
        launch(withArguments: ["-BPMockBrew"])

        // Two "Outdated" rows exist (Formulae + Casks); the formulae one is first.
        sidebarRow("sidebar.formulae.outdated").click()
        let git = formulaCell(withName: "mockgit")
        XCTAssertTrue(git.waitForExistence(timeout: 30.0), "mockgit should be in the Outdated list")
        git.click()

        let updateButton = app.buttons["Update Formula"]
        let appeared = updateButton.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "selecting an outdated formula should offer Update in the toolbar")
    }

    // Journey: clicking Update on an outdated formula asks for confirmation.
    func testUpgradePresentsConfirmationDialog() {
        launch(withArguments: ["-BPMockBrew"])

        // Two "Outdated" rows exist (Formulae + Casks); the formulae one is first.
        sidebarRow("sidebar.formulae.outdated").click()
        let git = formulaCell(withName: "mockgit")
        XCTAssertTrue(git.waitForExistence(timeout: 30.0), "mockgit should be in the Outdated list")
        git.click()

        let updateButton = app.buttons["Update Formula"]
        XCTAssertTrue(updateButton.waitForExistence(timeout: 15.0), "Update should be offered")
        updateButton.click()

        // upgradeSelectedFormulae: presents a Yes / Cancel confirmation sheet.
        let yesButton = app.buttons["Yes"]
        let confirmationAppeared = yesButton.waitForExistence(timeout: 15.0)
        if !confirmationAppeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(confirmationAppeared, "clicking Update should present a Yes/Cancel confirmation")

        // Cancel so the test doesn't proceed into the upgrade operation.
        dismissConfirmationSheet()
    }

    // Journey: running Doctor streams its report into the Doctor view.
    func testRunningDoctorShowsOutput() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.tools.doctor").click()
        XCTAssertTrue(
            app.staticTexts["Homebrew Doctor"].waitForExistence(timeout: 15.0),
            "the Doctor view should appear"
        )

        let runButton = app.buttons["Run Doctor"]
        XCTAssertTrue(runButton.waitForExistence(timeout: 15.0), "the Run Doctor button should exist")
        runButton.click()

        // The mock streams three chunks. Requiring the first marker *and* the last
        // in the same text view is the regression guard: the Doctor view used to
        // replace its whole document per chunk, so only the final chunk survived.
        let predicate = NSPredicate(
            format: "value CONTAINS %@ AND value CONTAINS %@",
            "MOCK_DOCTOR_OK",
            "MOCK_DOCTOR_DONE"
        )
        let output = app.textViews.matching(predicate).firstMatch
        let appeared = output.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "Doctor should accumulate every chunk, not just the last one")
    }

    // Journey: the toolbar's Update Homebrew button switches to the Update view and
    // streams the update output into it. The toolbar button (scoped via toolbars)
    // is used to avoid the name clash with the Update view's own button.
    func testRunningUpdateHomebrewShowsOutput() {
        launch(withArguments: ["-BPMockBrew"])

        let updateButton = app.toolbars.buttons["Update Homebrew"].firstMatch
        XCTAssertTrue(updateButton.waitForExistence(timeout: 15.0), "the toolbar Update Homebrew button should exist")
        updateButton.click()

        XCTAssertTrue(
            app.staticTexts["Homebrew Updater"].waitForExistence(timeout: 15.0),
            "clicking Update Homebrew should show the Update view"
        )

        let predicate = NSPredicate(format: "value CONTAINS %@", "MOCK_UPDATE_OK")
        let output = app.textViews.matching(predicate).firstMatch
        let appeared = output.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "running Update Homebrew should stream its output into the Update view")
    }

    // MARK: - Repository (tap/untap) journeys

    // Journey: with no repository selected, Tap offers a repo-name input dialog.
    func testTapPresentsInputDialog() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.formulae.repositories").click()

        let tapButton = app.buttons["Tap Repository"]
        XCTAssertTrue(tapButton.waitForExistence(timeout: 15.0), "Tap Repository should be offered")
        tapButton.click()

        // tapRepository: presents an OK/Cancel input dialog.
        let okButton = app.buttons["OK"]
        let appeared = okButton.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "Tap should present an input dialog with OK/Cancel")

        dismissConfirmationSheet()
    }

    // Journey: selecting a tapped repository and choosing Untap asks for confirmation.
    func testUntapPresentsConfirmationDialog() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.formulae.repositories").click()

        let repo = formulaCell(withName: "homebrew/core")
        let repoListed = repo.waitForExistence(timeout: 30.0)
        if !repoListed {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(repoListed, "a tapped repository should be listed")
        repo.click()

        let untapButton = app.buttons["Untap Repository"]
        XCTAssertTrue(untapButton.waitForExistence(timeout: 15.0), "Untap Repository should be offered")
        untapButton.click()

        // untapRepository: presents an OK/Cancel confirmation.
        let okButton = app.buttons["OK"]
        let appeared = okButton.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "Untap should present a confirmation with OK/Cancel")

        dismissConfirmationSheet()
    }

    // MARK: - Search journey

    // Journey: the toolbar provides a search field.
    //
    // The actual type-and-filter behaviour can't be driven here: the headless CI
    // session never makes the app window key, so no text field can take keyboard
    // focus (XCUITest reports "Neither element nor any descendant has keyboard
    // focus"). The search *filtering* logic is covered deterministically by a unit
    // test instead (BPHomebrewManagerTests testUpdateSearchFiltersAllFormulaeByName).
    func testSearchFieldIsAvailable() {
        launch(withArguments: ["-BPMockBrew"])
        XCTAssertTrue(
            formulaCell(withName: "mockwget").waitForExistence(timeout: 30.0),
            "the mock data should load"
        )

        let searchField = app.searchFields.firstMatch
        let exists = searchField.waitForExistence(timeout: 15.0)
        if !exists {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(exists, "the toolbar should provide a search field")
        XCTAssertTrue(searchField.isEnabled, "Search must accept input after the initial load, not just exist")
        XCTAssertGreaterThan(searchField.frame.size.width, 0.0)
        XCTAssertGreaterThan(searchField.frame.size.height, 0.0)
    }

    // MARK: - Formula info journey

    // A transient successful frame is not enough: the previous close animation can
    // still complete after a replacement popover has already rendered its content.
    func assertMockInformationSurvivesPopoverAnimation() {
        let settled = expectation(description: "popover close animation completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            settled.fulfill()
        }
        waitForExpectations(timeout: 5.0)
        let title = app.descendants(matching: .any)
            .matching(identifier: "formula.information.title")
            .firstMatch
        let information = app.descendants(matching: .any)
            .matching(identifier: "formula.information.text")
            .firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertTrue(title.label.contains("mockwget"))
        let content = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "A mock formula",
            "A mock formula"
        )
        XCTAssertTrue(information.exists)
        XCTAssertTrue(content.evaluate(with: information))
    }

    func testMoreInformationWhileOpenKeepsSelectedPackageContent() {
        launch(withArguments: ["-BPMockBrew"])
        formulaCell(withName: "mockwget").click()
        let infoButton = app.buttons["More Information"]
        infoButton.click()
        let information = app.descendants(matching: .any)
            .matching(identifier: "formula.information.text")
            .firstMatch
        XCTAssertTrue(information.waitForExistence(timeout: 15.0))
        infoButton.click()
        assertMockInformationSurvivesPopoverAnimation()
    }

    // Journey: More Information shows the selected formula's details in a popover.
    func testMoreInformationShowsFormulaInfoPopover() {
        launch(withArguments: ["-BPMockBrew"])

        let wget = formulaCell(withName: "mockwget")
        XCTAssertTrue(wget.waitForExistence(timeout: 30.0), "mockwget should be in the Installed list")
        wget.click()

        let infoButton = app.buttons["More Information"]
        XCTAssertTrue(infoButton.waitForExistence(timeout: 15.0), "More Information should be offered")
        infoButton.click()

        // The popover shows the formula's info (served by the mock interface).
        let infoText = app.descendants(matching: .any)
            .matching(identifier: "formula.information.text")
            .firstMatch
        let appeared = infoText.waitForExistence(timeout: 15.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "More Information should show the formula info in a popover")
        let content = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "A mock formula",
            "A mock formula"
        )
        expectation(for: content, evaluatedWith: infoText)
        waitForExpectations(timeout: 10.0)
        XCTAssertGreaterThan(infoText.frame.size.width, 100.0)
        XCTAssertGreaterThan(infoText.frame.size.height, 20.0)
        let title = app.descendants(matching: .any)
            .matching(identifier: "formula.information.title")
            .firstMatch
        XCTAssertTrue(title.label.contains("mockwget"))

        // An outside click dismisses the transient popover and keeps the selection.
        wget.click()
        let dismissed = NSPredicate(format: "exists == NO")
        expectation(for: dismissed, evaluatedWith: infoText)
        waitForExpectations(timeout: 10.0)
        infoButton.click()
        XCTAssertTrue(infoText.waitForExistence(timeout: 10.0), "the same selection can reopen information")
    }

    func testMoreInformationEscapeDismissesAndReopensSelectedPackage() {
        launch(withArguments: ["-BPMockBrew"])
        formulaCell(withName: "mockwget").click()
        let infoButton = app.buttons["More Information"]
        XCTAssertTrue(infoButton.waitForExistence(timeout: 15))
        infoButton.click()

        let popover = app.popovers.firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 15))
        let title = popover.descendants(matching: .any)
            .matching(identifier: "formula.information.title")
            .firstMatch
        let information = popover.descendants(matching: .any)
            .matching(identifier: "formula.information.text")
            .firstMatch
        XCTAssertTrue(information.waitForExistence(timeout: 15))
        let content = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "A mock formula",
            "A mock formula"
        )
        let loadedPopover = app.popovers.count == 1
            && title.exists
            && title.label.contains("mockwget")
            && content.evaluate(with: information)
        let applicationState = app.state
        XCTAssertTrue(loadedPopover)
        XCTAssertEqual(applicationState, .runningForeground)
        guard loadedPopover && applicationState == .runningForeground else { return }

        let beforeEscape = XCTAttachment(string: app.debugDescription)
        beforeEscape.name = "Loaded information before Escape"
        beforeEscape.lifetime = .keepAlways
        add(beforeEscape)
        app.typeKey(.escape, modifierFlags: [])
        let dismissed = popover.waitForNonExistence(timeout: 10)
        XCTAssertTrue(dismissed, "Escape must dismiss the actual popover container")
        guard dismissed else { return }
        XCTAssertFalse(title.exists)
        XCTAssertFalse(information.exists)

        infoButton.click()
        XCTAssertTrue(popover.waitForExistence(timeout: 10))
        XCTAssertTrue(
            information.waitForExistence(timeout: 10),
            "Reopening must restore the selected package information"
        )
        assertMockInformationSurvivesPopoverAnimation()
        XCTAssertFalse(app.sheets.firstMatch.exists)
    }

    // Moving between hosted information and hosted dependents views keeps both routes usable.
    func testInformationAndInstalledDependentsUseTheirOwnContent() {
        launch(withArguments: ["-BPMockBrew"])
        let wget = formulaCell(withName: "mockwget")
        wget.doubleClick()
        let information = app.descendants(matching: .any)
            .matching(identifier: "formula.information.text")
            .firstMatch
        XCTAssertTrue(information.waitForExistence(timeout: 15.0))
        wget.click()
        app.menuBars.menuBarItems["Formula"].click()
        app.menuItems["List Installed Dependents"].click()
        let dependentsTitle = app.descendants(matching: .any)
            .matching(identifier: "formula.dependents.title")
            .firstMatch
        let dependentsText = app.descendants(matching: .any)
            .matching(identifier: "formula.dependents.text")
            .firstMatch
        XCTAssertTrue(dependentsTitle.waitForExistence(timeout: 15.0))
        XCTAssertTrue(dependentsTitle.label.contains("Installed Dependents of Formula: mockwget"))
        XCTAssertTrue(dependentsText.waitForExistence(timeout: 15.0))
        let depContent = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@",
            "mockcurl",
            "mockcurl"
        )
        XCTAssertTrue(depContent.evaluate(with: dependentsText))
        XCTAssertFalse(information.exists)
        wget.click()
        app.buttons["More Information"].click()
        XCTAssertTrue(information.waitForExistence(timeout: 15.0))
        assertMockInformationSurvivesPopoverAnimation()
        XCTAssertFalse(dependentsTitle.exists)
    }

    // MARK: - Tools journeys

    // Opens Tools > Brew Cleanup and returns the confirmation sheet it presents.
    func beginCleanupAndWaitForSheet() -> XCUIElement {
        XCTAssertTrue(
            formulaCell(withName: "mockwget").waitForExistence(timeout: 30.0),
            "the mock data should load"
        )

        app.menuBars.menuBarItems["Tools"].click()
        let cleanupItem = app.menuItems["Brew Cleanup…"]
        XCTAssertTrue(cleanupItem.waitForExistence(timeout: 10.0), "Tools > Brew Cleanup should exist")
        cleanupItem.click()

        // Scoped to the sheet, not the app: an alert's buttons are mirrored to the
        // Touch Bar, so an app-wide query matches twice and firstMatch can pick the
        // mirror, which is not clickable.
        let sheet = app.sheets.firstMatch
        let appeared = sheet.waitForExistence(timeout: 20.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "Cleanup should preview what it would remove before deleting anything")
        return sheet
    }

    // Journey: a reload names the slow step in the footer rather than running silent.
    //
    // The loading overlay is built once at setup and comes down on the first
    // published list, so it cannot report the catalog fetch — which is the step
    // that takes 80+ seconds against real brew. -BPMockSlowCatalog holds the mock's
    // catalog calls long enough for the message to be observable.
    func testTheCatalogFetchSaysWhatItIsDoing() {
        launch(withArguments: ["-BPMockBrew", "-BPMockSlowCatalog"])

        let catalog = NSPredicate(
            format: "value CONTAINS %@ OR label CONTAINS %@",
            "cask catalog",
            "cask catalog"
        )
        let progress = app.staticTexts.matching(catalog).firstMatch

        let appeared = progress.waitForExistence(timeout: 30.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "the slow catalog fetch should say so rather than running silent")

        // And it gets out of the way: once the reload finishes the footer goes back
        // to describing the selected row.
        let description = NSPredicate(
            format: "value CONTAINS %@ OR label CONTAINS %@",
            "already installed",
            "already installed"
        )
        let restored = app.staticTexts.matching(description).firstMatch

        XCTAssertTrue(
            restored.waitForExistence(timeout: 30.0),
            "the footer should go back to the row description when the reload ends"
        )
    }

    // Journey: a running reload offers a way to stop it, and takes it away again.
    //
    // Deliberately not on the loading overlay: that comes down on the first
    // published list, about two seconds in, while the catalog fetch worth stopping
    // can take much longer. Hold the mock catalogs until cancellation so the
    // Stop control cannot disappear while the journey is locating it.
    func testAReloadCanBeStopped() {
        launch(withArguments: ["-BPMockBrew", "-BPMockHoldCatalogUntilCancelled"])

        let stop = app.buttons["Stop Reloading"]
        let appeared = stop.waitForExistence(timeout: 30.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "a running reload should offer a way to stop it")

        // Geometry rather than isHittable: hit testing needs a key window, which
        // the CI runner never has.
        XCTAssertTrue(
            stop.frame.size.width > 0 && stop.frame.size.height > 0,
            "the Stop control should have been laid out: \(NSStringFromRect(stop.frame))"
        )

        stop.click()

        // And it goes away, rather than sitting in the toolbar with nothing to stop.
        let gone = NSPredicate(format: "exists == NO")
        expectation(for: gone, evaluatedWith: stop)
        waitForExpectations(timeout: 30.0)
    }

    // Journey: Tools > Brew Cleanup previews what it would remove, and only cleans
    // up once that is confirmed.
    func testCleanupConfirmsThenStreamsOutput() {
        launch(withArguments: ["-BPMockBrew"])

        let sheet = beginCleanupAndWaitForSheet()

        // The preview has to name what will be lost. The mock's dry run reports
        // three items totalling 49.2MB, so the sheet must say so — a confirmation
        // that only says "are you sure" is the thing this replaced.
        let summary = NSPredicate(
            format: "value CONTAINS %@ OR label CONTAINS %@",
            "3 items",
            "3 items"
        )
        XCTAssertGreaterThan(
            sheet.staticTexts.matching(summary).count,
            0,
            "the sheet should say how much it would remove"
        )

        sheet.buttons["Yes"].click()

        let predicate = NSPredicate(format: "value CONTAINS %@", "MOCK_CLEANUP_OK")
        let output = app.textViews.matching(predicate).firstMatch
        let appeared = output.waitForExistence(timeout: 20.0)
        if !appeared {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(appeared, "confirming should run the cleanup and stream its output")
    }

    // Journey: cancelling the preview deletes nothing.
    //
    // The point of the sheet is the escape hatch, so this asserts the operation
    // window never opens — the mock's cleanup marker must never appear.
    func testCancellingCleanupRunsNothing() {
        launch(withArguments: ["-BPMockBrew"])

        let sheet = beginCleanupAndWaitForSheet()
        sheet.buttons["Cancel"].click()

        let predicate = NSPredicate(format: "value CONTAINS %@", "MOCK_CLEANUP_OK")
        let output = app.textViews.matching(predicate).firstMatch

        // Nothing to wait *for*, so wait for the window that would have opened and
        // assert it never does.
        XCTAssertFalse(
            output.waitForExistence(timeout: 5.0),
            "cancelling should not run a cleanup"
        )
    }

    // Journey: with nothing to remove, Cleanup says so instead of running.
    func testCleanupWithNothingToRemoveSaysSo() {
        launch(withArguments: ["-BPMockBrew", "-BPMockEmptyCleanup"])

        let sheet = beginCleanupAndWaitForSheet()

        XCTAssertTrue(
            sheet.buttons["OK"].exists,
            "the nothing-to-do sheet should acknowledge, not confirm a deletion"
        )
        XCTAssertFalse(
            sheet.buttons["Yes"].exists,
            "there is nothing to say yes to"
        )

        sheet.buttons["OK"].click()
    }

    func openMockExport(withArguments arguments: [String]) {
        launch(withArguments: ["-BPMockBrew", "-BPMockExportURL", "/fixture/Brewfile"] + arguments)
        app.menuBars.menuBarItems["Tools"].click()
        app.menuItems["Export Brew Installation…"].click()
    }

    func testExportShowsProgressUntilSuccessAndCloses() {
        openMockExport(withArguments: ["-BPMockSlowExport"])
        let close = app.sheets.firstMatch.buttons["brewfile.export.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 10))
        XCTAssertFalse(close.isEnabled)
        // AppKit spinners expose AXBusyIndicator, not the progress-bar AX role.
        let progress = app.descendants(matching: .any)["brewfile.export.progress"]
        if !progress.exists {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(progress.exists)
        XCTAssertFalse(app.staticTexts["brewfile.export.status"].exists)
        expectation(for: NSPredicate(format: "enabled == YES"), evaluatedWith: close)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(stringValue(of: app.staticTexts["brewfile.export.status"]).contains("Successful"))
        close.click()
        expectation(for: NSPredicate(format: "exists == NO"), evaluatedWith: app.sheets.firstMatch)
        waitForExpectations(timeout: 5)
    }

    func testExportFailureRemainsVisibleUntilClosed() {
        openMockExport(withArguments: ["-BPMockExportFails"])
        let status = app.staticTexts["brewfile.export.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(stringValue(of: status).contains("Failed"))
        XCTAssertTrue(stringValue(of: app.staticTexts["brewfile.export.detail"]).contains("MOCK_EXPORT_FAILED"))
        let close = app.sheets.firstMatch.buttons["brewfile.export.close"]
        XCTAssertTrue(close.isEnabled)
        close.click()
        expectation(for: NSPredicate(format: "exists == NO"), evaluatedWith: app.sheets.firstMatch)
        waitForExpectations(timeout: 5)
    }

    func testCancelledExportSaveLeavesAppReadyForAnotherOperation() {
        openMockExport(withArguments: ["-BPMockExportCancel"])
        XCTAssertFalse(app.sheets.firstMatch.exists)
        app.menuBars.menuBarItems["Tools"].click()
        app.menuItems["Import Brew Installation…"].click()
        XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 10))
        XCTAssertFalse(app.sheets.firstMatch.buttons["brewfile.export.close"].exists)
    }

    // Journey: the Tools menu exposes the Import / Export Brewfile actions.
    //
    // The full flow opens a system file panel (a separate process) and needs a
    // typed filename — neither is drivable under the CI key-window limit — so this
    // verifies the menu entry points are present rather than the whole operation.
    func testToolsMenuExposesImportAndExport() {
        launch(withArguments: ["-BPMockBrew"])
        XCTAssertTrue(
            formulaCell(withName: "mockwget").waitForExistence(timeout: 30.0),
            "the mock data should load"
        )

        app.menuBars.menuBarItems["Tools"].click()

        let exportPresent = app.menuItems["Export Brew Installation…"].waitForExistence(timeout: 10.0)
        let importPresent = app.menuItems["Import Brew Installation…"].exists
        if !exportPresent || !importPresent {
            NSLog("CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", app.debugDescription)
        }
        XCTAssertTrue(exportPresent, "Tools should offer Export Brew Installation")
        XCTAssertTrue(importPresent, "Tools should offer Import Brew Installation")
    }

    @discardableResult
    func openUpgradeAll(withArguments arguments: [String]) -> XCUIElement {
        launch(withArguments: ["-BPMockBrew"] + arguments)
        app.menuBars.menuBarItems["Formula"].click()
        let upgrade = app.menuItems["Upgrade All Updates…"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 15))
        let enabled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == YES"),
            object: upgrade
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        upgrade.click()
        let confirm = app.sheets.firstMatch.buttons["updates.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        return confirm
    }

    func testUpgradeAllKeyboardShortcutAndEscapeRunsNothing() {
        launch(withArguments: ["-BPMockBrew", "-BPMockMixedUpdates"])
        let ready = app.windows.firstMatch.exists
            && formulaCell(withName: "mockwget").exists
            && !app.sheets.firstMatch.exists
        let initialState = app.state
        XCTAssertTrue(ready)
        XCTAssertEqual(initialState, .runningForeground)
        guard ready && initialState == .runningForeground else { return }

        app.typeKey("u", modifierFlags: [.command, .option])
        let sheet = app.sheets.firstMatch
        let confirm = sheet.buttons["updates.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 15))
        let targets = sheet.textViews.matching(
            NSPredicate(
                format: "identifier == 'updates.targets' AND value CONTAINS 'Formulae: mockgit' AND value CONTAINS 'Casks: mockchrome'"
            )
        ).firstMatch
        let expectedConfirmation = confirm.exists && targets.exists
        let confirmationState = app.state
        XCTAssertTrue(expectedConfirmation)
        XCTAssertEqual(confirmationState, .runningForeground)
        guard expectedConfirmation && confirmationState == .runningForeground else { return }

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 10))
        let output = app.textViews.matching(
            NSPredicate(format: "value CONTAINS 'MOCK_UPGRADE_' OR value CONTAINS 'brew upgrade'")
        ).firstMatch
        XCTAssertFalse(output.exists)
    }

    func testUpgradeAllPinnedExclusionAndCancelRunsNothing() {
        openUpgradeAll(withArguments: [])
        let sheet = app.sheets.firstMatch
        let summary = sheet.textViews.matching(
            NSPredicate(
                format: "identifier == 'updates.targets' AND value CONTAINS 'Casks: mockchrome' AND value CONTAINS 'Pinned formulae will be skipped: mockgit'"
            )
        ).firstMatch
        XCTAssertTrue(summary.exists)
        sheet.buttons["Cancel"].click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 10))
        XCTAssertFalse(
            app.textViews.matching(NSPredicate(format: "value CONTAINS 'MOCK_UPGRADE_OK'")).firstMatch.exists
        )
    }

    func testUpgradeAllMixedConfirmationRunsExactNamesAndShowsCommandOutcomes() {
        let confirm = openUpgradeAll(withArguments: ["-BPMockMixedUpdates"])
        let summary = app.sheets.firstMatch.textViews.matching(
            NSPredicate(
                format: "identifier == 'updates.targets' AND value CONTAINS 'Formulae: mockgit' AND value CONTAINS 'Casks: mockchrome'"
            )
        ).firstMatch
        XCTAssertTrue(summary.exists)
        confirm.click()
        let output = app.sheets.firstMatch.textViews.matching(
            NSPredicate(
                format: "value CONTAINS 'Command succeeded: brew upgrade --formula mockgit' AND value CONTAINS 'Command succeeded: brew upgrade --cask mockchrome'"
            )
        ).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 15))
        app.sheets.firstMatch.buttons["OK"].click()
    }

    func testUpgradeAllLaterFailurePreservesFirstCommandSuccess() {
        let confirm = openUpgradeAll(withArguments: ["-BPMockMixedUpdates", "-BPMockFailedCaskUpgrade"])
        confirm.click()
        let output = app.sheets.firstMatch.textViews.matching(
            NSPredicate(
                format: "value CONTAINS 'Command succeeded: brew upgrade --formula mockgit' AND value CONTAINS 'Command failed; some packages may have changed: brew upgrade --cask mockchrome'"
            )
        ).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 15))
        app.sheets.firstMatch.buttons["OK"].click()
    }

    func testUpgradeAllCaskOnlyEnablesWithNoOutdatedFormulae() {
        let confirm = openUpgradeAll(withArguments: ["-BPMockEmptyOutdated"])
        confirm.click()
        let output = app.sheets.firstMatch.textViews.matching(
            NSPredicate(format: "value CONTAINS 'Command succeeded: brew upgrade --cask mockchrome'")
        ).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 15))
        XCTAssertFalse(stringValue(of: output).contains("--formula"))
        app.sheets.firstMatch.buttons["OK"].click()
    }

    func testUpgradeAllCancellationReportsActiveAndUnattemptedCommands() {
        let confirm = openUpgradeAll(withArguments: ["-BPMockMixedUpdates", "-BPMockSlowUpgrade"])
        confirm.click()
        let started = app.sheets.firstMatch.textViews.matching(
            NSPredicate(format: "value CONTAINS 'MOCK_UPGRADE_STARTED'")
        ).firstMatch
        XCTAssertTrue(started.waitForExistence(timeout: 15))
        app.sheets.firstMatch.buttons["Cancel"].click()
        let cancelling = app.sheets.firstMatch.textViews.matching(
            NSPredicate(format: "value CONTAINS 'MOCK_UPGRADE_CANCELLING'")
        ).firstMatch
        XCTAssertTrue(cancelling.waitForExistence(timeout: 10))
        XCTAssertFalse(app.sheets.firstMatch.buttons["OK"].isEnabled)
        let output = app.sheets.firstMatch.textViews.matching(
            NSPredicate(
                format: "value CONTAINS 'Command cancelled; some packages may have changed: brew upgrade --formula mockgit' AND value CONTAINS 'Command not attempted: brew upgrade --cask mockchrome'"
            )
        ).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.sheets.firstMatch.staticTexts.matching(
                NSPredicate(format: "value CONTAINS 'Homebrew task cancelled'")
            ).firstMatch.exists
        )
        app.sheets.firstMatch.buttons["OK"].click()
    }

    func testUnifiedUpdatesViewDisplaysBothFormulaAndCaskUpdatesAndUpgradesSelected() {
        launch(withArguments: ["-BPMockBrew", "-BPMockMixedUpdates"])
        let updatesSidebar = sidebarRow("sidebar.tools.updates")
        XCTAssertTrue(updatesSidebar.waitForExistence(timeout: 15.0))
        updatesSidebar.click()
        assertSelectedSidebarIdentifier("sidebar.tools.updates")

        XCTAssertTrue(
            formulaCell(withName: "mockgit").waitForExistence(timeout: 15.0),
            "Unified Updates should list outdated formulae"
        )
        XCTAssertTrue(
            formulaCell(withName: "mockchrome").waitForExistence(timeout: 15.0),
            "Unified Updates should list outdated casks"
        )

        let selectAllButton = app.buttons["unified.updates.selectAll"]
        XCTAssertTrue(selectAllButton.waitForExistence(timeout: 10.0))
        selectAllButton.click()

        let upgradeSelectedButton = app.buttons["unified.updates.upgradeSelected"]
        XCTAssertTrue(upgradeSelectedButton.exists)
        XCTAssertTrue(upgradeSelectedButton.isEnabled)
        upgradeSelectedButton.click()

        let yesButton = app.buttons["Yes"]
        XCTAssertTrue(
            yesButton.waitForExistence(timeout: 10.0),
            "Upgrading selected updates should present confirmation"
        )
        dismissConfirmationSheet()
    }

    func testUnifiedUpdatesViewShowsEmptyStateWhenUpToDate() {
        launch(withArguments: ["-BPMockBrew", "-BPMockEmptyOutdated", "-BPMockEmptyOutdatedCasks"])
        let updatesSidebar = sidebarRow("sidebar.tools.updates")
        XCTAssertTrue(updatesSidebar.waitForExistence(timeout: 15.0))
        updatesSidebar.click()
        assertSelectedSidebarIdentifier("sidebar.tools.updates")

        let upToDate = app.staticTexts["Everything is Up to Date"]
        XCTAssertTrue(
            upToDate.waitForExistence(timeout: 15.0),
            "Unified Updates should show the Everything is Up to Date empty state"
        )
    }

    func testLeavesSidebarRowListsLeafFormulae() {
        launch(withArguments: ["-BPMockBrew"])
        sidebarRow("sidebar.formulae.leaves").click()
        assertSelectedSidebarIdentifier("sidebar.formulae.leaves")
        XCTAssertTrue(
            formulaCell(withName: "mockack").waitForExistence(timeout: 15.0),
            "Leaves should list mockack"
        )
        XCTAssertTrue(
            formulaCell(withName: "mockwget").waitForExistence(timeout: 15.0),
            "Leaves should list mockwget"
        )
    }

    func testInstallFormulaWithOptionsSheetDisplaysOptionsAndCancels() {
        launch(withArguments: ["-BPMockBrew"])
        sidebarRow("sidebar.formulae.all").click()
        let htop = formulaCell(withName: "mockhtop")
        XCTAssertTrue(htop.waitForExistence(timeout: 15.0))
        htop.click()

        app.menuBars.menuBarItems["Formula"].click()
        let installWithOptions = app.menuItems["Install Formula with Options..."]
        XCTAssertTrue(installWithOptions.waitForExistence(timeout: 10.0))
        installWithOptions.click()

        let cancelButton = app.sheets.firstMatch.buttons["formula.options.cancel"]
        XCTAssertTrue(
            cancelButton.waitForExistence(timeout: 15.0),
            "Install with Options should present the SwiftUI options sheet"
        )
        cancelButton.click()
        XCTAssertTrue(app.sheets.firstMatch.waitForNonExistence(timeout: 10.0))
    }

    func testCheckForAppUpdatesMenuItemOpensUpdateWindowAndCloses() {
        launch(withArguments: ["-BPMockBrew"])
        app.menuBars.menuBarItems["Cakebrew"].click()
        let checkItem = app.menuItems["menu.app.checkForUpdates"]
        XCTAssertTrue(checkItem.waitForExistence(timeout: 10.0))
        checkItem.click()

        let closeButton = app.buttons["app.update.close"]
        XCTAssertTrue(
            closeButton.waitForExistence(timeout: 15.0),
            "Check for Updates should open the SwiftUI update discovery window"
        )
        closeButton.click()
    }

    func testDoctorAndUpdateClearLogButtonsClearTranscript() {
        launch(withArguments: ["-BPMockBrew"])

        sidebarRow("sidebar.tools.doctor").click()
        let runDoctor = app.buttons["Run Doctor"]
        XCTAssertTrue(runDoctor.waitForExistence(timeout: 15.0))
        runDoctor.click()

        let doctorDone = NSPredicate(format: "value CONTAINS %@", "MOCK_DOCTOR_DONE")
        let doctorOutput = app.textViews.matching(doctorDone).firstMatch
        XCTAssertTrue(doctorOutput.waitForExistence(timeout: 15.0))

        let clearButton = app.buttons["Clear Log"]
        XCTAssertTrue(clearButton.exists)
        clearButton.click()
        XCTAssertFalse(doctorOutput.exists)

        sidebarRow("sidebar.tools.update").click()
        var runUpdate = app.groups.buttons["Update Homebrew"].firstMatch
        if !runUpdate.exists {
            runUpdate = app.buttons.matching(identifier: "Update Homebrew").firstMatch
        }
        runUpdate.click()

        let updateDone = NSPredicate(format: "value CONTAINS %@", "MOCK_UPDATE_OK")
        let updateOutput = app.textViews.matching(updateDone).firstMatch
        XCTAssertTrue(updateOutput.waitForExistence(timeout: 15.0))
        app.buttons["Clear Log"].click()
        XCTAssertFalse(updateOutput.exists)
    }
}
