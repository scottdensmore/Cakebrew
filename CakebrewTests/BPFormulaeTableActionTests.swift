import XCTest
import AppKit
import Foundation

private final class BPTableActionRecorder: NSObject, BPFormulaeTableActionDelegate {
    var count: Int = 0
    var request: BPFormulaeTableRequest = .primary

    func formulaeTableView(_ table: BPFormulaeTableView, requestAction request: BPFormulaeTableRequest) {
        self.count += 1
        self.request = request
    }
}

@MainActor
final class BPFormulaeTableActionTests: XCTestCase, @unchecked Sendable {
    private var table: BPActionTestTable!
    private var recorder: BPTableActionRecorder!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
        table = BPActionTestTable(frame: NSMakeRect(0, 0, 500, 300))
        table.awakeFromNib()
        let windowStub = BPTableActionWindowStub()
        windowStub.firstResponder = table
        table.testWindow = windowStub
        table.testSelectedRow = 0
        recorder = BPTableActionRecorder()
        table.actionDelegate = recorder
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
        table.testWindow = nil
        table = nil
        recorder = nil
        }
        super.tearDown()
    }

    private func key(
        _ key: unichar,
        flags: NSEvent.ModifierFlags,
        repeat isRepeat: Bool,
        type: NSEvent.EventType
    ) -> NSEvent {
        let characters = String(utf16CodeUnits: [key], count: 1)
        return NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: 0
        )!
    }

    func testNativeDoubleActionOnlyRequestsPrimaryForASelectedExistingRow() {
        XCTAssertNotNil(table.doubleAction, "Native table doubleAction must be wired")
        guard table.doubleAction != nil else { return }
        XCTAssertTrue(table.target === table)
        XCTAssertEqual(table.doubleAction, #selector(BPFormulaeTableView.performDoubleClickAction(_:)))
        table.performDoubleClickAction(table)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(recorder.request, .primary)
        for row in [-1, 1, 2, 99] {
            table.testClickedRow = row
            table.performDoubleClickAction(table)
            XCTAssertEqual(recorder.count, 1, "Empty space, header, stale and unselected rows cannot act")
            XCTAssertEqual(table.testSelectedRow, 0, "Guarding the action must not change selection")
        }
    }

    func testPlainReturnKeypadEnterAndBothDeletesDispatchTypedRequests() {
        let keys: [unichar] = [0x0d, 0x03, 0x7f, 0xf728]
        for k in keys {
            recorder.count = 0
            XCTAssertTrue(table.performKeyEquivalent(with: key(k, flags: [], repeat: false, type: .keyDown)))
            XCTAssertEqual(recorder.count, 1)
            XCTAssertEqual(recorder.request, k < 0x7f ? .primary : .uninstall)
        }
    }

    func testShortcutModifiersAndRepeatsNeverDispatchNewActions() {
        let keys: [unichar] = [0x0d, 0x03, 0x7f, 0xf728]
        let modifierFlags: [NSEvent.ModifierFlags] = [.command, .option, .control, .shift]
        for k in keys {
            for flag in modifierFlags {
                XCTAssertFalse(table.performKeyEquivalent(with: key(k, flags: flag, repeat: false, type: .keyDown)))
            }
            XCTAssertFalse(table.performKeyEquivalent(with: key(k, flags: [], repeat: true, type: .keyDown)))
        }
        XCTAssertEqual(recorder.count, 0)
    }

    func testCapsLockFunctionAndNumericPadDoNotBlockRowActions() {
        let flags: [NSEvent.ModifierFlags] = [.capsLock, .function, .numericPad]
        for flag in flags {
            XCTAssertTrue(table.performKeyEquivalent(with: key(0x03, flags: flag, repeat: false, type: .keyDown)))
        }
        XCTAssertEqual(recorder.count, 3)
    }

    func testKeyUpOtherKeysNoSelectionAndOtherFocusDoNotDispatch() {
        XCTAssertFalse(table.performKeyEquivalent(with: key(0x0d, flags: [], repeat: false, type: .keyUp)))
        XCTAssertFalse(table.performKeyEquivalent(with: key(unichar(0x61), flags: [], repeat: false, type: .keyDown)))
        table.testSelectedRow = -1
        XCTAssertFalse(table.performKeyEquivalent(with: key(0x0d, flags: [], repeat: false, type: .keyDown)))
        table.testSelectedRow = 0
        table.testWindow = nil
        XCTAssertFalse(table.performKeyEquivalent(with: key(0x0d, flags: [], repeat: false, type: .keyDown)))
        XCTAssertEqual(recorder.count, 0)
    }

    func testSpacePreservesExistingModifiedAndRepeatingBehavior() {
        XCTAssertTrue(table.performKeyEquivalent(with: key(unichar(0x20), flags: .command, repeat: true, type: .keyDown)))
        XCTAssertEqual(table.spaceCount, 1)
        XCTAssertEqual(recorder.count, 0)
    }

    private func formula(_ cask: Bool) -> BPFormula {
        let f = BPFormula.formula(withName: "fixture")
        f.cask = cask
        return f
    }

    func testSingleSelectionMappingForEveryListNamespaceAndStatus() {
        for mode in BPListMode.all.rawValue...BPListMode.allCasks.rawValue {
            for cask in [false, true] {
                for status in BPFormulaStatus.notInstalled.rawValue...BPFormulaStatus.outdated.rawValue {
                    let isCaskMode = (mode == BPListMode.allCasks.rawValue
                        || mode == BPListMode.installedCasks.rawValue
                        || mode == BPListMode.outdatedCasks.rawValue)
                    let namespaceMatches = (mode == BPListMode.search.rawValue) || (cask == isCaskMode)
                    let valid = namespaceMatches && mode != BPListMode.repositories.rawValue
                    var primary: BPFormulaeTableAction = .none
                    if valid
                        && (mode == BPListMode.all.rawValue || mode == BPListMode.allCasks.rawValue)
                        && status == BPFormulaStatus.notInstalled.rawValue {
                        primary = .install
                    }
                    if valid
                        && (mode == BPListMode.installed.rawValue || mode == BPListMode.installedCasks.rawValue)
                        && status != BPFormulaStatus.notInstalled.rawValue {
                        primary = .info
                    }
                    if valid
                        && (mode == BPListMode.outdated.rawValue || mode == BPListMode.outdatedCasks.rawValue)
                        && status == BPFormulaStatus.outdated.rawValue {
                        primary = .upgrade
                    }
                    let stale = ((mode == BPListMode.installed.rawValue
                        || mode == BPListMode.installedCasks.rawValue
                        || mode == BPListMode.leaves.rawValue
                        || mode == BPListMode.pinned.rawValue) && status == BPFormulaStatus.notInstalled.rawValue)
                        || ((mode == BPListMode.outdated.rawValue || mode == BPListMode.outdatedCasks.rawValue)
                            && status != BPFormulaStatus.outdated.rawValue)
                    let deletion: BPFormulaeTableAction = (valid && !stale && status != BPFormulaStatus.notInstalled.rawValue)
                        ? .uninstall
                        : .none
                    let formulae = [formula(cask)]
                    XCTAssertEqual(
                        BPFormulaeTableActions.action(
                            forRequest: BPFormulaeTableRequest.primary.rawValue,
                            mode: mode,
                            formulae: formulae,
                            statuses: [NSNumber(value: status)]
                        ),
                        primary,
                        "mode=\(mode) cask=\(cask) status=\(status)"
                    )
                    XCTAssertEqual(
                        BPFormulaeTableActions.action(
                            forRequest: BPFormulaeTableRequest.uninstall.rawValue,
                            mode: mode,
                            formulae: formulae,
                            statuses: [NSNumber(value: status)]
                        ),
                        deletion,
                        "mode=\(mode) cask=\(cask) status=\(status)"
                    )
                }
            }
        }
    }

    func testOnlyHomogeneousOutdatedMultiSelectionCanUpgrade() {
        for mode in BPListMode.all.rawValue...BPListMode.allCasks.rawValue {
            let casks = (mode == BPListMode.outdatedCasks.rawValue)
            let formulae = [formula(casks), formula(casks)]
            let expected: BPFormulaeTableAction = (mode == BPListMode.outdated.rawValue || mode == BPListMode.outdatedCasks.rawValue)
                ? .upgrade
                : .none
            XCTAssertEqual(
                BPFormulaeTableActions.action(
                    forRequest: BPFormulaeTableRequest.primary.rawValue,
                    mode: mode,
                    formulae: formulae,
                    statuses: [2, 2]
                ),
                expected
            )
            XCTAssertEqual(
                BPFormulaeTableActions.action(
                    forRequest: BPFormulaeTableRequest.uninstall.rawValue,
                    mode: mode,
                    formulae: formulae,
                    statuses: [2, 2]
                ),
                .none
            )
        }
        XCTAssertEqual(
            BPFormulaeTableActions.action(
                forRequest: BPFormulaeTableRequest.primary.rawValue,
                mode: BPListMode.outdated.rawValue,
                formulae: [formula(false), formula(true)],
                statuses: [2, 2]
            ),
            .none
        )
        XCTAssertEqual(
            BPFormulaeTableActions.action(
                forRequest: BPFormulaeTableRequest.primary.rawValue,
                mode: BPListMode.outdated.rawValue,
                formulae: [formula(false), formula(false)],
                statuses: [2, 1]
            ),
            .none
        )
    }

    func testMissingMalformedUnknownAndStaleSelectionsFailClosed() {
        let invalidFormulae: [[Any]] = [[], ["not a model"], [BPFormula.formula(withName: "")]]
        for formulae in invalidFormulae {
            XCTAssertEqual(
                BPFormulaeTableActions.action(
                    forRequest: BPFormulaeTableRequest.primary.rawValue,
                    mode: BPListMode.all.rawValue,
                    formulae: formulae,
                    statuses: [0]
                ),
                .none
            )
        }
        let one = [formula(false)]
        let invalidStatuses: [[Any]] = [[], [99], [-1], ["bad"], [0, 0]]
        for statuses in invalidStatuses {
            XCTAssertEqual(
                BPFormulaeTableActions.action(
                    forRequest: BPFormulaeTableRequest.primary.rawValue,
                    mode: BPListMode.all.rawValue,
                    formulae: one,
                    statuses: statuses
                ),
                .none
            )
        }
        XCTAssertEqual(
            BPFormulaeTableActions.action(
                forRequest: 99,
                mode: BPListMode.all.rawValue,
                formulae: one,
                statuses: [0]
            ),
            .none
        )
        XCTAssertEqual(
            BPFormulaeTableActions.action(
                forRequest: BPFormulaeTableRequest.primary.rawValue,
                mode: 99,
                formulae: one,
                statuses: [0]
            ),
            .none
        )
    }

    func testReturnIsHandledByTheFocusedSelectedTable() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )!
        XCTAssertTrue(
            table.performKeyEquivalent(with: event),
            "Return should be handled locally by the focused selected formula table"
        )
    }

    func testToolbarModeForRepositoriesSidebarRow() {
        let row = Int(FormulaeSideBarItem.repositories.rawValue)
        for status in BPFormulaStatus.notInstalled.rawValue...BPFormulaStatus.outdated.rawValue {
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(forSidebarRow: row, selectedCount: 0, selectedFormulaStatus: status),
                .tap
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(forSidebarRow: row, selectedCount: 1, selectedFormulaStatus: status),
                .untap
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(forSidebarRow: row, selectedCount: 3, selectedFormulaStatus: status),
                .untap
            )
        }
    }

    func testToolbarModeForCaskSidebarRows() {
        let caskRows = [
            Int(FormulaeSideBarItem.installedCasks.rawValue),
            Int(FormulaeSideBarItem.outdatedCasks.rawValue),
            Int(FormulaeSideBarItem.allCasks.rawValue)
        ]
        for row in caskRows {
            for status in BPFormulaStatus.notInstalled.rawValue...BPFormulaStatus.outdated.rawValue {
                XCTAssertEqual(
                    BPFormulaeTableActions.toolbarMode(forSidebarRow: row, selectedCount: 0, selectedFormulaStatus: status),
                    .default
                )
            }
        }
        for status in BPFormulaStatus.notInstalled.rawValue...BPFormulaStatus.outdated.rawValue {
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(
                    forSidebarRow: Int(FormulaeSideBarItem.installedCasks.rawValue),
                    selectedCount: 1,
                    selectedFormulaStatus: status
                ),
                .uninstall
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(
                    forSidebarRow: Int(FormulaeSideBarItem.installedCasks.rawValue),
                    selectedCount: 2,
                    selectedFormulaStatus: status
                ),
                .uninstall
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(
                    forSidebarRow: Int(FormulaeSideBarItem.outdatedCasks.rawValue),
                    selectedCount: 1,
                    selectedFormulaStatus: status
                ),
                .updateSingle
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(
                    forSidebarRow: Int(FormulaeSideBarItem.outdatedCasks.rawValue),
                    selectedCount: 2,
                    selectedFormulaStatus: status
                ),
                .updateMany
            )
        }
        let allCasksRow = Int(FormulaeSideBarItem.allCasks.rawValue)
        XCTAssertEqual(
            BPFormulaeTableActions.toolbarMode(
                forSidebarRow: allCasksRow,
                selectedCount: 1,
                selectedFormulaStatus: BPFormulaStatus.notInstalled.rawValue
            ),
            .install
        )
        XCTAssertEqual(
            BPFormulaeTableActions.toolbarMode(
                forSidebarRow: allCasksRow,
                selectedCount: 1,
                selectedFormulaStatus: BPFormulaStatus.installed.rawValue
            ),
            .uninstall
        )
        XCTAssertEqual(
            BPFormulaeTableActions.toolbarMode(
                forSidebarRow: allCasksRow,
                selectedCount: 1,
                selectedFormulaStatus: BPFormulaStatus.outdated.rawValue
            ),
            .uninstall
        )
    }

    func testToolbarModeForFormulaSidebarRowsToolsAndOutOfBounds() {
        let formulaRows = [
            Int(FormulaeSideBarItem.installed.rawValue),
            Int(FormulaeSideBarItem.outdated.rawValue),
            Int(FormulaeSideBarItem.all.rawValue),
            Int(FormulaeSideBarItem.leaves.rawValue),
            Int(FormulaeSideBarItem.pinned.rawValue)
        ]
        for row in formulaRows {
            for status in BPFormulaStatus.notInstalled.rawValue...BPFormulaStatus.outdated.rawValue {
                XCTAssertEqual(
                    BPFormulaeTableActions.toolbarMode(forSidebarRow: row, selectedCount: 0, selectedFormulaStatus: status),
                    .default
                )
                XCTAssertEqual(
                    BPFormulaeTableActions.toolbarMode(forSidebarRow: row, selectedCount: 2, selectedFormulaStatus: status),
                    .updateMany
                )
            }
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(
                    forSidebarRow: row,
                    selectedCount: 1,
                    selectedFormulaStatus: BPFormulaStatus.notInstalled.rawValue
                ),
                .install
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(
                    forSidebarRow: row,
                    selectedCount: 1,
                    selectedFormulaStatus: BPFormulaStatus.installed.rawValue
                ),
                .uninstall
            )
            let expectedOutdated: BPToolbarMode = (row == Int(FormulaeSideBarItem.outdated.rawValue))
                ? .updateSingle
                : .uninstall
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(
                    forSidebarRow: row,
                    selectedCount: 1,
                    selectedFormulaStatus: BPFormulaStatus.outdated.rawValue
                ),
                expectedOutdated
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(forSidebarRow: row, selectedCount: 1, selectedFormulaStatus: 99),
                .default
            )
        }

        let nonFormulaRows = [
            -1,
            -99,
            Int(FormulaeSideBarItem.doctor.rawValue),
            Int(FormulaeSideBarItem.update.rawValue),
            Int(FormulaeSideBarItem.services.rawValue),
            99
        ]
        for row in nonFormulaRows {
            for count: UInt in [0, 1, 2] {
                XCTAssertEqual(
                    BPFormulaeTableActions.toolbarMode(
                        forSidebarRow: row,
                        selectedCount: count,
                        selectedFormulaStatus: BPFormulaStatus.installed.rawValue
                    ),
                    .default
                )
            }
        }

        let unifiedRow = Int(FormulaeSideBarItem.unifiedUpdates.rawValue)
        for status in BPFormulaStatus.notInstalled.rawValue...BPFormulaStatus.outdated.rawValue {
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(forSidebarRow: unifiedRow, selectedCount: 0, selectedFormulaStatus: status),
                .default
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(forSidebarRow: unifiedRow, selectedCount: 1, selectedFormulaStatus: status),
                .updateSingle
            )
            XCTAssertEqual(
                BPFormulaeTableActions.toolbarMode(forSidebarRow: unifiedRow, selectedCount: 2, selectedFormulaStatus: status),
                .updateMany
            )
        }
    }

    func testShouldShowFormulaInfoHidesDetailOnlyOnRepositoriesRow() {
        let maxRow = Int(FormulaeSideBarItem.services.rawValue) + 2
        for row in -1...maxRow {
            let expected = (row != Int(FormulaeSideBarItem.repositories.rawValue))
            XCTAssertEqual(
                BPFormulaeTableActions.shouldShowFormulaInfo(forSidebarRow: row),
                expected,
                "row=\(row)"
            )
        }
    }

    func testFooterLocalizationKeyPrefersSearchAndDelegatesRowMapping() {
        let maxRow = Int(FormulaeSideBarItem.services.rawValue) + 1
        for row in -1...maxRow {
            XCTAssertEqual(
                BPFormulaeTableActions.footerLocalizationKey(forSidebarRow: row, searching: true),
                "Sidebar_Info_SearchResults",
                "row=\(row)"
            )
            XCTAssertEqual(
                BPFormulaeTableActions.footerLocalizationKey(forSidebarRow: row, searching: false),
                BPSideBarController.infoKey(forRow: row),
                "row=\(row)"
            )
        }
        XCTAssertNil(BPFormulaeTableActions.footerLocalizationKey(forSidebarRow: Int(FormulaeSideBarItem.formulaeCategory.rawValue), searching: false))
        XCTAssertNil(BPFormulaeTableActions.footerLocalizationKey(forSidebarRow: Int(FormulaeSideBarItem.casksCategory.rawValue), searching: false))
        XCTAssertNil(BPFormulaeTableActions.footerLocalizationKey(forSidebarRow: Int(FormulaeSideBarItem.toolsCategory.rawValue), searching: false))
        XCTAssertNil(BPFormulaeTableActions.footerLocalizationKey(forSidebarRow: -1, searching: false))
        XCTAssertEqual(
            BPFormulaeTableActions.footerLocalizationKey(forSidebarRow: Int(FormulaeSideBarItem.installed.rawValue), searching: false),
            "Sidebar_Info_Installed"
        )
    }

    func testShouldRefreshVisibleListRequiresLoadedMatchingMode() {
        for published in BPListMode.all.rawValue...BPListMode.allCasks.rawValue {
            for active in BPListMode.all.rawValue...BPListMode.allCasks.rawValue {
                XCTAssertFalse(
                    BPFormulaeTableActions.shouldRefreshVisibleList(
                        forPublishedMode: published,
                        activeMode: active,
                        isLoading: true
                    )
                )
                XCTAssertEqual(
                    BPFormulaeTableActions.shouldRefreshVisibleList(
                        forPublishedMode: published,
                        activeMode: active,
                        isLoading: false
                    ),
                    published == active
                )
            }
        }
    }

    func testShouldSyncInstalledHostMetadataOnlyForSecondaryMetadataListsWhenLoadedAndHosted() {
        for published in BPListMode.all.rawValue...BPListMode.allCasks.rawValue {
            for active in BPListMode.all.rawValue...BPListMode.allCasks.rawValue {
                let isMetadataMode = (published == BPListMode.pinned.rawValue
                    || published == BPListMode.outdated.rawValue
                    || published == BPListMode.outdatedCasks.rawValue)
                for loading in [false, true] {
                    for hosted in [false, true] {
                        let expected = !loading && hosted && (active != published) && isMetadataMode
                        XCTAssertEqual(
                            BPFormulaeTableActions.shouldSyncInstalledHostMetadata(
                                forPublishedMode: published,
                                activeMode: active,
                                isLoading: loading,
                                isUsingInstalledHost: hosted
                            ),
                            expected,
                            "published=\(published) active=\(active) loading=\(loading) hosted=\(hosted)"
                        )
                    }
                }
            }
        }
    }

    func testShouldSyncUnifiedUpdatesForPublishedMode() {
        for published in BPListMode.all.rawValue...BPListMode.allCasks.rawValue {
            let isUpdatesMode = (published == BPListMode.outdated.rawValue
                || published == BPListMode.outdatedCasks.rawValue
                || published == BPListMode.pinned.rawValue)
            for loading in [false, true] {
                for hosted in [false, true] {
                    let expected = !loading && hosted && isUpdatesMode
                    XCTAssertEqual(
                        BPFormulaeTableActions.shouldSyncUnifiedUpdates(
                            forPublishedMode: published,
                            isLoading: loading,
                            isUsingUnifiedUpdatesHost: hosted
                        ),
                        expected
                    )
                }
            }
        }
    }

    // MARK: - BPPackageOperationPresenter

    func testPresenterInstallAndUninstallAlertsAndZapCheckbox() {
        XCTAssertNil(BPPackageOperationPresenter.installAlert(forFormula: nil))
        XCTAssertNil(BPPackageOperationPresenter.installAlert(forFormula: BPFormula.formula(withName: "")))

        let formula = BPFormula.formula(withName: "wget")
        let installAlert = BPPackageOperationPresenter.installAlert(forFormula: formula)
        XCTAssertNotNil(installAlert)
        XCTAssertEqual(installAlert?.buttons.count, 2)
        XCTAssertTrue(installAlert?.informativeText.contains("wget") ?? false)

        XCTAssertNil(BPPackageOperationPresenter.uninstallAlert(forFormula: nil, initialZapState: true))
        let uninstallFormulaAlert = BPPackageOperationPresenter.uninstallAlert(
            forFormula: formula,
            initialZapState: true
        )
        let formulaCheckbox = uninstallFormulaAlert?.accessoryView as? NSButton
        XCTAssertNotNil(uninstallFormulaAlert)
        XCTAssertNil(formulaCheckbox)
        XCTAssertNil(uninstallFormulaAlert?.accessoryView)
        XCTAssertTrue(uninstallFormulaAlert?.informativeText.contains("wget") ?? false)

        let cask = BPFormula.formula(withName: "firefox")
        cask.cask = true
        let uninstallCaskAlertOn = BPPackageOperationPresenter.uninstallAlert(
            forFormula: cask,
            initialZapState: true
        )
        let caskCheckboxOn = uninstallCaskAlertOn?.accessoryView as? NSButton
        XCTAssertNotNil(uninstallCaskAlertOn)
        XCTAssertNotNil(caskCheckboxOn)
        XCTAssertEqual(caskCheckboxOn?.state, .on)
        XCTAssertEqual(uninstallCaskAlertOn?.accessoryView, caskCheckboxOn)

        let uninstallCaskAlertOff = BPPackageOperationPresenter.uninstallAlert(
            forFormula: cask,
            initialZapState: false
        )
        let caskCheckboxOff = uninstallCaskAlertOff?.accessoryView as? NSButton
        XCTAssertEqual(caskCheckboxOff?.state, .off)
    }

    func testPresenterUpgradeSelectedAndUpgradeAllAlertsAndSummaries() {
        XCTAssertNil(BPPackageOperationPresenter.upgradeAlert(forFormulae: nil))
        XCTAssertNil(BPPackageOperationPresenter.upgradeAlert(forFormulae: []))
        XCTAssertNil(BPPackageOperationPresenter.upgradeAlert(forFormulae: [BPFormula.formula(withName: "")]))

        let git = BPFormula.formula(withName: "git")
        let iterm = BPFormula.formula(withName: "iterm2")
        iterm.cask = true
        let upgradeAlert = BPPackageOperationPresenter.upgradeAlert(forFormulae: [git, iterm])
        XCTAssertNotNil(upgradeAlert)
        XCTAssertEqual(upgradeAlert?.buttons.count, 2)
        XCTAssertTrue(upgradeAlert?.informativeText.contains("git, iterm2") ?? false)

        XCTAssertNil(BPPackageOperationPresenter.updatesReviewSummary(forSnapshot: nil))
        XCTAssertNil(BPPackageOperationPresenter.upgradeAllAlert(forSnapshot: nil))

        let emptySnapshot = BPUpdatesSnapshot(
            generation: 1,
            formulaItems: [],
            caskItems: [],
            pinnedFormulaNames: [],
            pinnedCaskNames: []
        )
        XCTAssertNil(BPPackageOperationPresenter.updatesReviewSummary(forSnapshot: emptySnapshot))
        XCTAssertNil(BPPackageOperationPresenter.upgradeAllAlert(forSnapshot: emptySnapshot))

        let pinnedFormula = BPFormula.formula(withName: "openssl")
        let pinnedCask = BPFormula.formula(withName: "docker")
        pinnedCask.cask = true
        let mixedSnapshot = BPUpdatesSnapshot(
            generation: 2,
            formulae: [git, pinnedFormula],
            casks: [iterm, pinnedCask],
            pinnedFormulae: [pinnedFormula],
            pinnedCasks: [pinnedCask]
        )
        let summary = BPPackageOperationPresenter.updatesReviewSummary(forSnapshot: mixedSnapshot)
        XCTAssertNotNil(summary)
        XCTAssertTrue(summary?.contains("git") ?? false)
        XCTAssertTrue(summary?.contains("iterm2") ?? false)
        XCTAssertTrue(summary?.contains("openssl") ?? false)
        XCTAssertTrue(summary?.contains("docker") ?? false)

        let upgradeAllAlert = BPPackageOperationPresenter.upgradeAllAlert(forSnapshot: mixedSnapshot)
        XCTAssertNotNil(upgradeAllAlert)
        XCTAssertEqual(upgradeAllAlert?.buttons.count, 2)
        XCTAssertEqual(upgradeAllAlert?.buttons.first?.accessibilityIdentifier(), "updates.confirm")
        XCTAssertTrue(upgradeAllAlert?.accessoryView is NSScrollView)

        let changedAlert = BPPackageOperationPresenter.updatesChangedAlert()
        XCTAssertNotNil(changedAlert)
        XCTAssertEqual(changedAlert.buttons.count, 1)
    }

    func testPresenterTapUntapCleanupBrewfileInventoriesAndResolvedSelection() {
        let tapAlert = BPPackageOperationPresenter.tapInputAlert()
        let tapHost = BPPackageOperationPresenter.tapInputHost(for: tapAlert)
        let inputField = tapHost?.inputField
        XCTAssertNotNil(tapAlert)
        XCTAssertNotNil(inputField)
        XCTAssertNotNil(tapAlert.accessoryView)
        XCTAssertNotNil(tapHost)
        XCTAssertEqual(tapHost?.inputField, inputField)
        XCTAssertFalse(tapHost?.isValidFormat ?? true)
        tapHost?.repositoryName = "homebrew/cask"
        XCTAssertTrue(tapHost?.isValidFormat ?? false)
        XCTAssertEqual(inputField?.stringValue, "homebrew/cask")
        XCTAssertEqual(tapAlert.buttons.count, 2)

        let invalidTap = BPPackageOperationPresenter.invalidTapAlert()
        XCTAssertNotNil(invalidTap)
        XCTAssertEqual(invalidTap.buttons.count, 1)

        XCTAssertNil(BPPackageOperationPresenter.untapAlert(forFormula: nil))
        let repo = BPFormula.formula(withName: "homebrew/cask")
        let untapAlert = BPPackageOperationPresenter.untapAlert(forFormula: repo)
        XCTAssertNotNil(untapAlert)
        XCTAssertTrue(untapAlert?.informativeText.contains("homebrew/cask") ?? false)

        let emptyPreview = BPCleanupPreview.preview(fromOutput: "")
        let emptyCleanupAlert = BPPackageOperationPresenter.cleanupAlert(for: emptyPreview)
        XCTAssertEqual(emptyCleanupAlert.buttons.count, 1)
        XCTAssertNil(BPPackageOperationPresenter.cleanupPreviewHost(for: emptyCleanupAlert))

        let noSizePreview = BPCleanupPreview.preview(fromOutput: "Would remove: /tmp/a\n")
        let noSizeBody = BPPackageOperationPresenter.cleanupConfirmationBody(for: noSizePreview)
        XCTAssertGreaterThan(noSizeBody.count, 0)
        let nonEmptyCleanupAlert = BPPackageOperationPresenter.cleanupAlert(for: noSizePreview)
        XCTAssertEqual(nonEmptyCleanupAlert.buttons.count, 2)
        let cleanupHost = BPPackageOperationPresenter.cleanupPreviewHost(for: nonEmptyCleanupAlert)
        XCTAssertNotNil(cleanupHost)
        XCTAssertEqual(cleanupHost?.itemCount, 1)

        let sizedPreview = BPCleanupPreview.preview(
            fromOutput: "Would remove: /tmp/a (10KB)\nWould remove: /tmp/b (20KB)\n==> This operation would free approximately 100MB of disk space.\n"
        )
        let sizedBody = BPPackageOperationPresenter.cleanupConfirmationBody(for: sizedPreview)
        XCTAssertGreaterThan(sizedBody.count, 0)

        let brewPkg = BPFormula.formula(withName: "wget")
        let caskPkg = BPFormula.formula(withName: "firefox")
        caskPkg.cask = true
        let inventories = BPPackageOperationPresenter.brewfileInventories(
            forInstalledFormulae: [brewPkg],
            installedCasks: [caskPkg],
            repositories: [repo]
        )
        XCTAssertEqual(inventories["brew"], ["wget"])
        XCTAssertEqual(inventories["cask"], ["firefox"])
        XCTAssertEqual(inventories["tap"], ["homebrew/cask"])
        let emptyInventories = BPPackageOperationPresenter.brewfileInventories(
            forInstalledFormulae: nil,
            installedCasks: nil,
            repositories: nil
        )
        XCTAssertTrue(emptyInventories.isEmpty)

        // Heterogeneous resolution preserves namespace flags and uses live manager models when present
        let sharedFormula = BPFormula.formula(withName: "shared", andVersion: "1.0")
        let sharedCask = BPFormula.formula(withName: "shared", andVersion: "2.0")
        sharedCask.cask = true
        let resolved = BPPackageOperationPresenter.resolvedSelection(
            forFormulaNames: ["shared", "fallback-formula"],
            caskNames: ["shared", "fallback-cask"],
            outdatedFormulae: [sharedFormula],
            outdatedCasks: [sharedCask]
        ).compactMap { $0 as? BPFormula }
        XCTAssertEqual(resolved.count, 4)
        XCTAssertEqual(resolved[0], sharedFormula)
        XCTAssertFalse(resolved[0].cask)
        XCTAssertEqual(resolved[1].name, "fallback-formula")
        XCTAssertFalse(resolved[1].cask)
        XCTAssertEqual(resolved[2], sharedCask)
        XCTAssertTrue(resolved[2].cask)
        XCTAssertEqual(resolved[3].name, "fallback-cask")
        XCTAssertTrue(resolved[3].cask)
    }
}
