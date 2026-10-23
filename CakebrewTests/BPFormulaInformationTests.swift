import CryptoKit
import XCTest

final class BPFormulaInformationTests: XCTestCase {
    func testNewSelectionRejectsEarlierResponse() {
        var state = BPFormulaInformationState()
        let old = state.begin(name: "wget", cask: false)
        let current = state.begin(name: "git", cask: false)
        XCTAssertFalse(state.receive(request: old, information: "old", website: nil))
        XCTAssertTrue(state.receive(request: current, information: "current", website: nil))
        XCTAssertEqual(state.information, "current")
    }

    func testSameNameInDifferentNamespacesIsDistinct() {
        var state = BPFormulaInformationState()
        let formula = state.begin(name: "tap/tools/shared", cask: false)
        let cask = state.begin(name: "tap/tools/shared", cask: true)
        XCTAssertNotEqual(formula.identity, cask.identity)
        XCTAssertEqual(cask.identity.name, "tap/tools/shared")
        XCTAssertFalse(state.receive(request: formula, information: "formula", website: nil))
        XCTAssertTrue(state.receive(request: cask, information: "cask", website: nil))
    }

    func testRepeatedSelectionRejectsPreviousGeneration() {
        var state = BPFormulaInformationState()
        let first = state.begin(name: "wget", cask: false)
        let second = state.begin(name: "wget", cask: false)
        XCTAssertEqual(first.identity, second.identity)
        XCTAssertNotEqual(first.generation, second.generation)
        XCTAssertFalse(state.receive(request: first, information: "old", website: nil))
        XCTAssertTrue(state.receive(request: second, information: "new", website: nil))
    }

    func testClosingOrChangingModeInvalidatesPendingInformation() {
        var state = BPFormulaInformationState()
        let request = state.begin(name: "wget", cask: false)
        state.close()
        XCTAssertFalse(state.receive(request: request, information: "late", website: nil))
        XCTAssertNil(state.request)
    }

    func testNilAndEmptyResultsFinishLoadingWithoutFabricatedContent() {
        for information in [nil, "", "  \n"] as [String?] {
            var state = BPFormulaInformationState()
            let request = state.begin(name: "wget", cask: false)
            XCTAssertTrue(state.isLoading)
            XCTAssertTrue(state.receive(request: request, information: information, website: nil))
            XCTAssertFalse(state.isLoading)
            XCTAssertNil(state.information)
            XCTAssertNil(state.website)
        }
    }

    func testResponsePreservesTextAndWebsite() {
        var state = BPFormulaInformationState()
        let request = state.begin(name: "wget", cask: false)
        let url = URL(string: "https://example.org/wget")!
        XCTAssertTrue(state.receive(request: request, information: "First\nSecond", website: url))
        XCTAssertEqual(state.information, "First\nSecond")
        XCTAssertEqual(state.website, url)
    }

    func testLinkDetectionPreservesSelectableTextAndUnicodeRanges() {
        let cases: [(String, [String])] = [
            ("Café ☕\nhttps://example.com/cask\nUnlinked final line",
             ["https://example.com/cask"]),
            ("🍰 mockwget\nhttps://example.com/formula/mockwget\nDetails: https://example.org/docs?q=brew\nPlain description.",
             ["https://example.com/formula/mockwget", "https://example.org/docs?q=brew"]),
            ("Ordinary package information with no links.", [])
        ]
        for (source, URLs) in cases {
            let result = BPFormulaInformationAttributedText(source)
            XCTAssertEqual(String(result.characters), source)
            let links = result.runs.filter { $0.link != nil }
            XCTAssertEqual(links.count, URLs.count)
            for (run, URLString) in zip(links, URLs) {
                let linkedText = String(result[run.range].characters)
                let prefix = String(result[result.startIndex..<run.range.lowerBound].characters)
                let actualRange = NSRange(location: prefix.utf16.count, length: linkedText.utf16.count)
                XCTAssertEqual(run.link, URL(string: URLString))
                XCTAssertEqual(linkedText, URLString)
                XCTAssertEqual(actualRange, (source as NSString).range(of: URLString))
            }
            XCTAssertNil(result.runs.first?.link)
        }
    }

    func testChangingPopoverModeForSamePackageRejectsEarlierModeResponse() {
        var state = BPFormulaInformationState()
        let general = state.begin(name: "wget", cask: false, mode: .general)
        let installedDependents = state.begin(name: "wget", cask: false, mode: .installedDependents)
        XCTAssertNotEqual(general.identity, installedDependents.identity)
        XCTAssertFalse(state.receive(request: general, information: "general info", website: nil))
        XCTAssertTrue(state.receive(request: installedDependents, information: "git\ncurl\n", website: nil))
        XCTAssertEqual(state.information, "git\ncurl\n")

        let allDependents = state.begin(name: "wget", cask: false, mode: .allDependents)
        XCTAssertNotEqual(installedDependents.identity, allDependents.identity)
        XCTAssertFalse(state.receive(request: installedDependents, information: "stale installed", website: nil))
        XCTAssertTrue(state.receive(request: allDependents, information: "git\ncurl\nhtop\n", website: nil))
        XCTAssertEqual(state.information, "git\ncurl\nhtop\n")
    }

    func testSelectedFormulaStateEmptyAndMultipleSelectionValues() {
        var state = BPSelectedFormulaState()
        XCTAssertEqual(state.selection, .none)
        XCTAssertFalse(state.showsPinnedRow)

        let request = state.beginSingle(BPSelectedFormulaSnapshot(
            name: "wget", cask: false, isInstalled: true, isPinned: true,
            installPath: "/opt/homebrew/Cellar/wget/1.24", latestVersion: "1.24",
            dependencies: "openssl", conflicts: nil, shortDescription: "Internet file retriever"))
        XCTAssertTrue(state.showsPinnedRow)

        state.selectMultiple()
        XCTAssertEqual(state.selection, .multiple)
        XCTAssertFalse(state.showsPinnedRow)
        XCTAssertFalse(state.receiveDependents(["git"], for: request))

        state.clear()
        XCTAssertEqual(state.selection, .none)
        XCTAssertFalse(state.receiveDependents(["git"], for: request))
    }

    func testSelectedFormulaStateSameNameDifferentNamespaceRejectsStaleUpdatesAndDependents() {
        var state = BPSelectedFormulaState()
        let formulaSnapshot = BPSelectedFormulaSnapshot(
            name: "tap/tools/shared", cask: false, isInstalled: true, isPinned: true,
            installPath: "/opt/homebrew/Cellar/shared/1.0", latestVersion: "1.0",
            dependencies: "openssl", conflicts: "legacy-shared", shortDescription: "Shared formula")
        let caskSnapshot = BPSelectedFormulaSnapshot(
            name: "tap/tools/shared", cask: true, isInstalled: false, isPinned: true,
            installPath: nil, latestVersion: "2.0",
            dependencies: nil, conflicts: nil, shortDescription: "Shared cask")

        let formulaRequest = state.beginSingle(formulaSnapshot)
        XCTAssertTrue(state.showsPinnedRow)

        let caskRequest = state.beginSingle(caskSnapshot)
        XCTAssertNotEqual(formulaRequest.identity, caskRequest.identity)
        XCTAssertFalse(state.showsPinnedRow, "Casks must never display the Pinned row even if passed isPinned=true")
        XCTAssertFalse(state.receiveDependents(["git"], for: formulaRequest))
        XCTAssertFalse(state.receiveDependents(["git"], for: caskRequest), "Casks do not accept brew uses dependents")
        XCTAssertFalse(state.updateSingle(formulaSnapshot), "Stale formula update must not overwrite same-named cask")
    }

    func testSelectedFormulaStateMetadataUpdatePreservesActiveGenerationAndDependents() {
        var state = BPSelectedFormulaState()
        let initial = BPSelectedFormulaSnapshot(
            name: "wget", cask: false, isInstalled: true, isPinned: false,
            installPath: nil, latestVersion: "1.24",
            dependencies: nil, conflicts: nil, shortDescription: nil)
        let request = state.beginSingle(initial)
        XCTAssertTrue(state.receiveDependents(["curl", "git"], for: request))
        XCTAssertEqual(state.dependents, ["curl", "git"])

        let enriched = BPSelectedFormulaSnapshot(
            name: "wget", cask: false, isInstalled: true, isPinned: true,
            installPath: "/opt/homebrew/Cellar/wget/1.24", latestVersion: "1.24 (bottled)",
            dependencies: "gettext, libidn2, openssl@3", conflicts: "wget-devel",
            shortDescription: "Internet file retriever")
        XCTAssertTrue(state.updateSingle(enriched))
        XCTAssertEqual(state.dependents, ["curl", "git"])
        XCTAssertTrue(state.showsPinnedRow)
        XCTAssertEqual(state.currentSnapshot, enriched)
    }

    func testInstalledPackageRowStripsCaskPinAndPreservesNamespaceIdentity() {
        let formulaRow = BPInstalledPackageRow(
            name: "shared",
            cask: false,
            version: "1.0",
            latestVersion: "1.1",
            statusRank: 2,
            isPinned: true)
        let caskRow = BPInstalledPackageRow(
            name: "shared",
            cask: true,
            version: "2.0",
            latestVersion: "2.0",
            statusRank: 1,
            isPinned: true)

        XCTAssertNotEqual(formulaRow.id, caskRow.id)
        XCTAssertTrue(formulaRow.isPinned)
        XCTAssertFalse(caskRow.isPinned, "Casks cannot be pinned")
    }

    func testInstalledPackageListStateSortsByNameVersionAndStatusStably() {
        var state = BPInstalledPackageListState()
        let rows = [
            BPInstalledPackageRow(name: "Wget", cask: false, version: "9.0", latestVersion: "9.0", statusRank: 2, isPinned: false),
            BPInstalledPackageRow(name: "ack", cask: false, version: "10.0", latestVersion: "10.0", statusRank: 1, isPinned: false),
            BPInstalledPackageRow(name: "git", cask: false, version: "2.0", latestVersion: "2.0", statusRank: 1, isPinned: true),
            BPInstalledPackageRow(name: "curl", cask: false, version: "2.0", latestVersion: "2.0", statusRank: 0, isPinned: false)
        ]
        state.replaceRows(rows, isCaskList: false)

        // Default unsort preserves incoming order
        XCTAssertEqual(state.displayedRows.map(\.name), ["Wget", "ack", "git", "curl"])

        // Case-insensitive Name sort
        state.setSort(column: .name, ascending: true)
        XCTAssertEqual(state.displayedRows.map(\.name), ["ack", "curl", "git", "Wget"])

        state.setSort(column: .name, ascending: false)
        XCTAssertEqual(state.displayedRows.map(\.name), ["Wget", "git", "curl", "ack"])

        // Natural Version sort with stable tie-breaking (git before curl at version 2.0)
        state.setSort(column: .version, ascending: true)
        XCTAssertEqual(state.displayedRows.map(\.name), ["git", "curl", "Wget", "ack"])

        // Enum Status sort (0 < 1 < 2) with stable tie-breaking (ack before git at rank 1)
        state.setSort(column: .status, ascending: true)
        XCTAssertEqual(state.displayedRows.map(\.name), ["curl", "ack", "git", "Wget"])
    }

    func testInstalledPackageListStatePreservesSelectionAcrossReloadAndSort() {
        var state = BPInstalledPackageListState()
        let initial = [
            BPInstalledPackageRow(name: "wget", cask: false, version: "1.24", latestVersion: "1.24", statusRank: 1, isPinned: false),
            BPInstalledPackageRow(name: "git", cask: false, version: "2.44", latestVersion: "2.44", statusRank: 1, isPinned: true)
        ]
        state.replaceRows(initial, isCaskList: false)
        XCTAssertTrue(state.select(name: "git", cask: false))
        XCTAssertEqual(state.selectedRowIndex, 1)

        // Sorting moves "git" to index 0; selection stays on "git"
        state.setSort(column: .name, ascending: true)
        XCTAssertEqual(state.displayedRows.map(\.name), ["git", "wget"])
        XCTAssertEqual(state.selectedRowIndex, 0)
        XCTAssertEqual(state.selectedRow?.name, "git")

        // Reloading with "git" still present keeps selection; reloading without "git" clears it
        state.replaceRows(initial, isCaskList: false)
        XCTAssertEqual(state.selectedRow?.name, "git")

        // Same name in cask namespace does not match formula selection
        let casks = [
            BPInstalledPackageRow(name: "git", cask: true, version: "2.44", latestVersion: "2.44", statusRank: 1, isPinned: false)
        ]
        state.replaceRows(casks, isCaskList: true)
        XCTAssertNil(state.selectedID)
        XCTAssertEqual(state.selectedRowIndex, -1)
    }

    func testPackageListModeColumnAndNamespaceProperties() {
        XCTAssertEqual(BPPackageListMode.installedFormulae.rawValue, 0)
        XCTAssertEqual(BPPackageListMode.outdatedFormulae.rawValue, 1)
        XCTAssertEqual(BPPackageListMode.allFormulae.rawValue, 2)
        XCTAssertEqual(BPPackageListMode.leaves.rawValue, 3)
        XCTAssertEqual(BPPackageListMode.pinned.rawValue, 4)
        XCTAssertEqual(BPPackageListMode.search.rawValue, 5)
        XCTAssertEqual(BPPackageListMode.installedCasks.rawValue, 6)
        XCTAssertEqual(BPPackageListMode.outdatedCasks.rawValue, 7)
        XCTAssertEqual(BPPackageListMode.allCasks.rawValue, 8)
        XCTAssertEqual(BPPackageListMode.repositories.rawValue, 9)
        XCTAssertEqual(BPPackageListMode(rawMode: 999), .installedFormulae)

        let allModes: [BPPackageListMode] = [
            .installedFormulae, .outdatedFormulae, .allFormulae, .leaves, .pinned,
            .search, .installedCasks, .outdatedCasks, .allCasks, .repositories
        ]
        for mode in allModes {
            XCTAssertEqual(mode.showsVersionColumn, mode != .repositories)
            XCTAssertEqual(mode.showsLatestVersionColumn, mode == .outdatedFormulae || mode == .outdatedCasks)
            XCTAssertEqual(mode.showsStatusColumn, mode == .allFormulae || mode == .allCasks || mode == .search)
            XCTAssertEqual(mode.isCaskMode, mode == .installedCasks || mode == .outdatedCasks || mode == .allCasks)
        }
    }

    func testInstalledPackageListStateSupportsMultiModeAndMixedNamespaceSearch() {
        var state = BPInstalledPackageListState()
        XCTAssertEqual(state.mode, .installedFormulae)
        XCTAssertFalse(state.isCaskList)

        state.setMode(.outdatedCasks)
        XCTAssertEqual(state.mode, .outdatedCasks)
        XCTAssertTrue(state.isCaskList)

        let searchRows = [
            BPInstalledPackageRow(name: "shared", cask: false, version: "1.0", latestVersion: "1.1", statusRank: 2, isPinned: false),
            BPInstalledPackageRow(name: "shared", cask: true, version: "2.0", latestVersion: "2.0", statusRank: 1, isPinned: false),
            BPInstalledPackageRow(name: "wget", cask: false, version: "", latestVersion: "1.24", statusRank: 0, isPinned: false)
        ]
        state.replaceRows(searchRows, mode: .search)
        XCTAssertEqual(state.mode, .search)
        XCTAssertFalse(state.isCaskList)

        XCTAssertEqual(state.index(ofName: "shared", cask: false), 0)
        XCTAssertEqual(state.index(ofName: "shared", cask: true), 1)
        XCTAssertTrue(state.select(name: "shared", cask: true))
        XCTAssertEqual(state.selectedRowIndex, 1)
        XCTAssertEqual(state.selectedRow?.cask, true)

        // LatestVersion sort for outdated modes
        let outdatedRows = [
            BPInstalledPackageRow(name: "pkgA", cask: false, version: "1.0", latestVersion: "1.10.0", statusRank: 2, isPinned: false),
            BPInstalledPackageRow(name: "pkgB", cask: false, version: "1.0", latestVersion: "1.2.0", statusRank: 2, isPinned: false)
        ]
        state.replaceRows(outdatedRows, mode: .outdatedFormulae)
        state.setSort(column: .latestVersion, ascending: true)
        XCTAssertEqual(state.displayedRows.map(\.name), ["pkgB", "pkgA"])
    }

    func testUnifiedUpdatesStateEmptyFormulaOnlyAndCaskOnly() {
        var state = BPUnifiedUpdatesState()
        XCTAssertTrue(state.isEmpty)
        XCTAssertFalse(state.hasFormulaUpdates)
        XCTAssertFalse(state.hasCaskUpdates)
        XCTAssertEqual(state.selectedFormulaNames, [])
        XCTAssertEqual(state.selectedCaskNames, [])

        // Formula-only
        let formulaOnly = [
            BPUnifiedUpdateRow(name: "git", cask: false, version: "2.43", latestVersion: "2.44", isPinned: false),
            BPUnifiedUpdateRow(name: "wget", cask: false, version: "1.23", latestVersion: "1.24", isPinned: false)
        ]
        state.replace(formulaRows: formulaOnly, caskRows: [])
        XCTAssertFalse(state.isEmpty)
        XCTAssertTrue(state.hasFormulaUpdates)
        XCTAssertFalse(state.hasCaskUpdates)

        state.selectAllEligible()
        XCTAssertEqual(state.selectedFormulaNames, ["git", "wget"])
        XCTAssertEqual(state.selectedCaskNames, [])

        // Cask-only
        let caskOnly = [
            BPUnifiedUpdateRow(name: "iterm2", cask: true, version: "3.4", latestVersion: "3.5", isPinned: false)
        ]
        state.replace(formulaRows: [], caskRows: caskOnly)
        XCTAssertFalse(state.isEmpty)
        XCTAssertFalse(state.hasFormulaUpdates)
        XCTAssertTrue(state.hasCaskUpdates)
        XCTAssertEqual(state.selectedFormulaNames, [])
        XCTAssertEqual(state.selectedCaskNames, [])

        state.selectAllEligible()
        XCTAssertEqual(state.selectedFormulaNames, [])
        XCTAssertEqual(state.selectedCaskNames, ["iterm2"])
    }

    func testUnifiedUpdatesStateMixedPinnedExclusionsAndNamespaceSeparation() {
        let formulaRows = [
            BPUnifiedUpdateRow(name: "shared", cask: false, version: "1.0", latestVersion: "1.1", isPinned: false),
            BPUnifiedUpdateRow(name: "pinned-formula", cask: false, version: "2.0", latestVersion: "2.1", isPinned: true),
            BPUnifiedUpdateRow(name: "curl", cask: false, version: "8.0", latestVersion: "8.1", isPinned: false)
        ]
        let caskRows = [
            BPUnifiedUpdateRow(name: "shared", cask: true, version: "4.0", latestVersion: "4.1", isPinned: false),
            BPUnifiedUpdateRow(name: "pinned-cask", cask: true, version: "5.0", latestVersion: "5.1", isPinned: true),
            BPUnifiedUpdateRow(name: "firefox", cask: true, version: "120.0", latestVersion: "121.0", isPinned: false)
        ]

        var state = BPUnifiedUpdatesState(formulaRows: formulaRows, caskRows: caskRows)
        XCTAssertTrue(state.hasFormulaUpdates)
        XCTAssertTrue(state.hasCaskUpdates)
        XCTAssertFalse(state.isEmpty)

        // Pinned rows are ineligible and excluded from selectAllEligible
        state.selectAllEligible()
        XCTAssertEqual(state.selectedFormulaNames, ["shared", "curl"])
        XCTAssertEqual(state.selectedCaskNames, ["shared", "firefox"])

        // Selecting only eligible formulae clears cask selection and never mixes namespaces
        state.selectEligibleFormulae()
        XCTAssertEqual(state.selectedFormulaNames, ["shared", "curl"])
        XCTAssertEqual(state.selectedCaskNames, [])

        // Selecting only eligible casks clears formula selection and never mixes namespaces
        state.selectEligibleCasks()
        XCTAssertEqual(state.selectedFormulaNames, [])
        XCTAssertEqual(state.selectedCaskNames, ["shared", "firefox"])

        // Clear selection
        state.clearSelection()
        XCTAssertEqual(state.selectedFormulaNames, [])
        XCTAssertEqual(state.selectedCaskNames, [])

        // Toggling a pinned item refuses selection
        let pinnedFormulaID = BPFormulaInformationIdentity(name: "pinned-formula", cask: false)
        XCTAssertFalse(state.toggleSelection(for: pinnedFormulaID))
        XCTAssertTrue(state.selectedIDs.isEmpty)

        // Toggling same-named formula does not select same-named cask
        let sharedFormulaID = BPFormulaInformationIdentity(name: "shared", cask: false)
        let sharedCaskID = BPFormulaInformationIdentity(name: "shared", cask: true)
        XCTAssertTrue(state.toggleSelection(for: sharedFormulaID))
        XCTAssertEqual(state.selectedFormulaNames, ["shared"])
        XCTAssertEqual(state.selectedCaskNames, [])

        XCTAssertTrue(state.toggleSelection(for: sharedCaskID))
        XCTAssertEqual(state.selectedFormulaNames, ["shared"])
        XCTAssertEqual(state.selectedCaskNames, ["shared"])

        // Reloading preserves still-eligible selections and drops newly-pinned or removed items
        let reloadedFormulae = [
            BPUnifiedUpdateRow(name: "shared", cask: false, version: "1.0", latestVersion: "1.1", isPinned: true),
            BPUnifiedUpdateRow(name: "curl", cask: false, version: "8.0", latestVersion: "8.1", isPinned: false)
        ]
        state.replace(formulaRows: reloadedFormulae, caskRows: caskRows)
        XCTAssertEqual(state.selectedFormulaNames, [], "Newly pinned formula must be dropped from selection")
        XCTAssertEqual(state.selectedCaskNames, ["shared"], "Still-eligible cask selection must be preserved")
    }

    @MainActor
    func testInstalledPackageListHostMultiModeAndUnifiedUpdatesHostCallbacks() {
        let listHost = BPInstalledPackageListHost()
        XCTAssertEqual(listHost.listMode, BPPackageListMode.installedFormulae.rawValue)

        listHost.updateRows(
            names: ["shared", "shared"],
            versions: ["1.0", "2.0"],
            latestVersions: ["1.1", "2.0"],
            statusRanks: [2, 1],
            pinnedFlags: [false, false],
            caskFlags: [false, true],
            mode: BPPackageListMode.search.rawValue)
        XCTAssertEqual(listHost.listMode, BPPackageListMode.search.rawValue)
        XCTAssertEqual(listHost.rowCount, 2)
        XCTAssertTrue(listHost.selectPackage(named: "shared", cask: true))
        XCTAssertEqual(listHost.selectedRow, 1)
        XCTAssertEqual(listHost.selectedPackageName, "shared")
        XCTAssertTrue(listHost.selectedPackageCask)

        let updatesHost = BPUnifiedUpdatesHost()
        var selectionCallbacks = 0
        var upgradeAllCount = 0
        var upgradedPairs: [([String], [String])] = []
        updatesHost.onSelectionChanged = { selectionCallbacks += 1 }
        updatesHost.onUpgradeSelected = { formulae, casks in
            upgradedPairs.append((formulae, casks))
        }
        updatesHost.onUpgradeAll = { upgradeAllCount += 1 }

        XCTAssertTrue(updatesHost.isEmpty)
        XCTAssertEqual(updatesHost.rowCount, 0)
        XCTAssertEqual(updatesHost.selectedCount, 0)
        XCTAssertFalse(updatesHost.hasEligibleUpdates)

        updatesHost.update(
            formulaNames: ["git", "pinned-formula"],
            formulaVersions: ["2.43", "1.0"],
            formulaLatestVersions: ["2.44", "1.1"],
            formulaPinnedFlags: [false, true],
            caskNames: ["iterm2"],
            caskVersions: ["3.4"],
            caskLatestVersions: ["3.5"],
            caskPinnedFlags: [false])
        XCTAssertFalse(updatesHost.isEmpty)
        XCTAssertEqual(updatesHost.rowCount, 3)
        XCTAssertEqual(updatesHost.selectedCount, 0)
        XCTAssertTrue(updatesHost.hasEligibleUpdates)
        XCTAssertTrue(updatesHost.hasFormulaUpdates)
        XCTAssertTrue(updatesHost.hasCaskUpdates)

        updatesHost.selectAllEligible()
        XCTAssertEqual(updatesHost.selectedFormulaNames, ["git"])
        XCTAssertEqual(updatesHost.selectedCaskNames, ["iterm2"])
        XCTAssertEqual(updatesHost.selectedCount, 2)
        XCTAssertEqual(selectionCallbacks, 1)

        updatesHost.upgradeSelected()
        XCTAssertEqual(upgradedPairs.count, 1)
        XCTAssertEqual(upgradedPairs.first?.0, ["git"])
        XCTAssertEqual(upgradedPairs.first?.1, ["iterm2"])

        updatesHost.upgradeAll()
        XCTAssertEqual(upgradeAllCount, 1)

        updatesHost.selectFormulaGroup()
        XCTAssertEqual(updatesHost.selectedFormulaNames, ["git"])
        XCTAssertEqual(updatesHost.selectedCaskNames, [])
        XCTAssertEqual(updatesHost.selectedCount, 1)

        updatesHost.selectCaskGroup()
        XCTAssertEqual(updatesHost.selectedFormulaNames, [])
        XCTAssertEqual(updatesHost.selectedCaskNames, ["iterm2"])
        XCTAssertEqual(updatesHost.selectedCount, 1)

        updatesHost.clearSelection()
        XCTAssertEqual(updatesHost.selectedFormulaNames, [])
        XCTAssertEqual(updatesHost.selectedCaskNames, [])
        XCTAssertEqual(updatesHost.selectedCount, 0)

        updatesHost.filterQuery = "git"
        XCTAssertEqual(updatesHost.filterQuery, "git")
    }

    func testInstalledPackageListStateTenThousandRowsSortAndLookupPerformance() {
        var rows: [BPInstalledPackageRow] = []
        rows.reserveCapacity(10_000)
        for index in 0..<10_000 {
            let name = String(format: "pkg-%05d", 9_999 - index)
            let isCask = (index % 2 == 1)
            let statusRank = index % 3
            rows.append(BPInstalledPackageRow(
                name: name,
                cask: isCask,
                version: "\(index % 20).\(index % 10).0",
                latestVersion: "\(index % 20).\(index % 10).1",
                statusRank: statusRank,
                isPinned: index % 50 == 0))
        }

        var state = BPInstalledPackageListState()
        state.replaceRows(rows, mode: .search)
        XCTAssertEqual(state.displayedRows.count, 10_000)

        // O(1) lookup before sorting
        XCTAssertEqual(state.index(ofName: "pkg-09999", cask: false), 0)
        XCTAssertEqual(state.index(ofName: "pkg-00000", cask: true), 9_999)

        // Sort 10,000 rows by Name ascending
        state.setSort(column: .name, ascending: true)
        XCTAssertEqual(state.displayedRows.first?.name, "pkg-00000")
        XCTAssertEqual(state.displayedRows.last?.name, "pkg-09999")
        XCTAssertEqual(state.index(ofName: "pkg-00000", cask: true), 0)
        XCTAssertEqual(state.index(ofName: "pkg-09999", cask: false), 9_999)

        // Selection and O(1) selectedRowIndex after sort
        XCTAssertTrue(state.select(name: "pkg-05000", cask: true))
        XCTAssertEqual(state.selectedRowIndex, 5_000)
        XCTAssertEqual(state.selectedRow?.name, "pkg-05000")
    }

    func testAppVersionParsingAndSemanticOrdering() {
        let v1_2 = BPAppVersion(parsing: "v1.2")
        let v1_2_0 = BPAppVersion(parsing: "1.2.0")
        let v1_10_0 = BPAppVersion(parsing: "1.10.0")
        let v2_0_beta1 = BPAppVersion(parsing: "2.0.0-beta.1")
        let v2_0_beta2 = BPAppVersion(parsing: "2.0.0-beta.2+build99")
        let v2_0_final = BPAppVersion(parsing: "V2.0.0")

        XCTAssertNotNil(v1_2)
        XCTAssertEqual(v1_2?.major, 1)
        XCTAssertEqual(v1_2?.minor, 2)
        XCTAssertEqual(v1_2?.patch, 0)
        XCTAssertEqual(v1_2?.major, v1_2_0?.major)
        XCTAssertFalse(v1_2! < v1_2_0!)
        XCTAssertFalse(v1_2_0! < v1_2!)

        XCTAssertTrue(v1_2_0! < v1_10_0!)
        XCTAssertTrue(v1_10_0! < v2_0_beta1!)
        XCTAssertTrue(v2_0_beta1! < v2_0_beta2!)
        XCTAssertTrue(v2_0_beta2! < v2_0_final!)

        XCTAssertNil(BPAppVersion(parsing: ""))
        XCTAssertNil(BPAppVersion(parsing: "1"))
        XCTAssertNil(BPAppVersion(parsing: "1.2.3.4"))
        XCTAssertNil(BPAppVersion(parsing: "1.a.0"))
        XCTAssertNil(BPAppVersion(parsing: "1.2.0-"))
    }

    func testAppUpdateVerifierSHA256AndEd25519SignatureVerification() throws {
        let sampleArchive = Data("Cakebrew-2.1.0.dmg-binary-payload".utf8)
        let digestHex = BPAppUpdateVerifier.sha256Hex(of: sampleArchive)
        XCTAssertEqual(digestHex.count, 64)
        XCTAssertTrue(BPAppUpdateVerifier.isValidSHA256Hex(digestHex))
        XCTAssertTrue(BPAppUpdateVerifier.verifySHA256(data: sampleArchive, expectedHex: digestHex.uppercased()))
        XCTAssertFalse(BPAppUpdateVerifier.verifySHA256(data: Data("tampered".utf8), expectedHex: digestHex))
        XCTAssertFalse(BPAppUpdateVerifier.isValidSHA256Hex("short"))

        let privateKey = Curve25519.Signing.PrivateKey()
        let publicKeyBase64 = privateKey.publicKey.rawRepresentation.base64EncodedString()

        let unsignedRelease = BPAppUpdateRelease(
            version: BPAppVersion(parsing: "2.1.0")!,
            title: "Cakebrew 2.1.0",
            releaseNotes: "Swift 6 Tahoe modernization.",
            downloadURL: URL(string: "https://github.com/scottdensmore/Cakebrew/releases/download/v2.1.0/Cakebrew-2.1.0.dmg")!,
            sha256Hex: digestHex)
        let signatureData = try privateKey.signature(for: unsignedRelease.canonicalSignedPayload)
        let signatureBase64 = signatureData.base64EncodedString()

        let validFeed: [String: Any] = [
            "version": "2.1.0",
            "title": "Cakebrew 2.1.0",
            "releaseNotes": "Swift 6 Tahoe modernization.",
            "downloadURL": "https://github.com/scottdensmore/Cakebrew/releases/download/v2.1.0/Cakebrew-2.1.0.dmg",
            "sha256": digestHex,
            "ed25519Signature": signatureBase64
        ]
        let feedData = try JSONSerialization.data(withJSONObject: validFeed)
        let parsed = BPAppUpdateVerifier.parseFeed(data: feedData, publicKeyBase64: publicKeyBase64)
        XCTAssertEqual(try parsed.get().version, BPAppVersion(parsing: "2.1.0"))

        // Tampered URL or version must fail Ed25519 signature verification
        var tamperedFeed = validFeed
        tamperedFeed["downloadURL"] = "https://evil.example.com/Cakebrew-2.1.0.dmg"
        let tamperedData = try JSONSerialization.data(withJSONObject: tamperedFeed)
        XCTAssertEqual(
            BPAppUpdateVerifier.parseFeed(data: tamperedData, publicKeyBase64: publicKeyBase64),
            .failure(.invalidSignature))

        // Non-HTTPS downloadURL must be rejected even without signature check
        var insecureFeed = validFeed
        insecureFeed["downloadURL"] = "http://github.com/scottdensmore/Cakebrew/releases/download/v2.1.0/Cakebrew.dmg"
        let insecureData = try JSONSerialization.data(withJSONObject: insecureFeed)
        XCTAssertEqual(
            BPAppUpdateVerifier.parseFeed(data: insecureData, publicKeyBase64: nil),
            .failure(.insecureDownloadURL))
    }

    @MainActor
    func testAppUpdateStateAndHostsLifecycle() throws {
        var state = BPAppUpdateState(currentVersionString: "1.5.0")
        let staleGen = state.beginCheck(currentVersionString: "1.5.0")
        let activeGen = state.beginCheck(currentVersionString: "1.5.0")
        XCTAssertEqual(state.phase, .checking)

        let digestHex = BPAppUpdateVerifier.sha256Hex(of: Data("archive".utf8))
        let feedJSON: [String: Any] = [
            "version": "2.0.0",
            "title": "Cakebrew 2.0",
            "releaseNotes": "Tahoe Redesign",
            "downloadURL": "https://github.com/scottdensmore/Cakebrew/releases/download/v2.0.0/Cakebrew.dmg",
            "sha256": digestHex
        ]
        let feedData = try JSONSerialization.data(withJSONObject: feedJSON)

        XCTAssertFalse(state.receiveFeedData(feedData, publicKeyBase64: nil, generation: staleGen))
        XCTAssertTrue(state.receiveFeedData(feedData, publicKeyBase64: nil, generation: activeGen))
        if case .updateAvailable(let release, _) = state.phase {
            XCTAssertEqual(release.version, BPAppVersion(parsing: "2.0.0"))
        } else {
            XCTFail("Expected updateAvailable phase, got \(state.phase)")
        }

        let host = BPAppUpdateHost(currentVersion: "2.0.0", automaticCheckEnabled: true)
        let hostGen = host.beginCheck(currentVersion: "2.0.0")
        XCTAssertTrue(host.isChecking)
        XCTAssertTrue(host.receiveFeedData(feedData, publicKeyBase64: nil, generation: hostGen))
        XCTAssertFalse(host.isUpdateAvailable, "Same version 2.0.0 must report upToDate, not updateAvailable")

        let prefsHost = BPPreferencesHost()
        prefsHost.sync(
            backgroundCheckEnabled: true,
            interval: 3600.0,
            greedy: true,
            automaticAppUpdates: true,
            helperStatus: "Ready",
            helperActionTitle: nil)
        XCTAssertNotNil(prefsHost.viewController.view)
    }

    @MainActor
    func testObjCListModeMappingMultiSelectionAndTahoeSurfaceHosts() {
        // Verify all 10 Objective-C BPListMode values map to the expected BPPackageListMode
        XCTAssertEqual(BPPackageListMode(objcListMode: 0), .allFormulae)
        XCTAssertEqual(BPPackageListMode(objcListMode: 1), .installedFormulae)
        XCTAssertEqual(BPPackageListMode(objcListMode: 2), .leaves)
        XCTAssertEqual(BPPackageListMode(objcListMode: 3), .outdatedFormulae)
        XCTAssertEqual(BPPackageListMode(objcListMode: 4), .search)
        XCTAssertEqual(BPPackageListMode(objcListMode: 5), .repositories)
        XCTAssertEqual(BPPackageListMode(objcListMode: 6), .pinned)
        XCTAssertEqual(BPPackageListMode(objcListMode: 7), .installedCasks)
        XCTAssertEqual(BPPackageListMode(objcListMode: 8), .outdatedCasks)
        XCTAssertEqual(BPPackageListMode(objcListMode: 9), .allCasks)

        XCTAssertTrue(BPPackageListMode.outdatedFormulae.allowsMultipleSelection)
        XCTAssertTrue(BPPackageListMode.outdatedCasks.allowsMultipleSelection)
        XCTAssertFalse(BPPackageListMode.installedFormulae.allowsMultipleSelection)
        XCTAssertFalse(BPPackageListMode.allFormulae.showsInstalledVersionColumn)
        XCTAssertFalse(BPPackageListMode.allCasks.showsInstalledVersionColumn)
        XCTAssertFalse(BPPackageListMode.search.showsInstalledVersionColumn)
        XCTAssertTrue(BPPackageListMode.installedFormulae.showsInstalledVersionColumn)
        XCTAssertTrue(BPPackageListMode.outdatedFormulae.showsInstalledVersionColumn)

        // Multi-selection in BPInstalledPackageListState & BPInstalledPackageListHost
        let listHost = BPInstalledPackageListHost()
        listHost.updateRowsForObjCMode(
            names: ["wget", "git", "curl"],
            versions: ["1.0", "2.0", "3.0"],
            latestVersions: ["1.1", "2.1", "3.1"],
            statusRanks: [2, 2, 2],
            pinnedFlags: [false, false, false],
            caskFlags: [false, false, false],
            objcListMode: 3)
        XCTAssertEqual(listHost.rowCount, 3)
        XCTAssertTrue(listHost.selectPackage(named: "git", cask: false))
        XCTAssertEqual(listHost.selectedCount, 1)
        XCTAssertEqual(listHost.selectedPackageNames, ["git"])
        XCTAssertEqual(listHost.selectedPackageCasks, [NSNumber(value: false)])

        var listState = BPInstalledPackageListState()
        listState.replaceRows([
            BPInstalledPackageRow(name: "a", cask: false, version: "1.0", latestVersion: "1.1", statusRank: 2, isPinned: false),
            BPInstalledPackageRow(name: "b", cask: false, version: "2.0", latestVersion: "2.1", statusRank: 2, isPinned: false),
            BPInstalledPackageRow(name: "c", cask: false, version: "3.0", latestVersion: "3.1", statusRank: 2, isPinned: false)
        ], mode: .outdatedFormulae)
        XCTAssertTrue(listState.selectRows(at: IndexSet([0, 2])))
        XCTAssertEqual(listState.selectedRows.map(\.name), ["a", "c"])
        XCTAssertEqual(listState.selectedRowIndexes, [0, 2])
        // Switching to a single-selection mode collapses multi-selection to 1 row
        listState.setMode(.installedFormulae)
        XCTAssertEqual(listState.selectedIDs.count, 1)

        // Verify Tahoe surface state models and hosts
        let emptyHost = BPEmptyStateHost(symbolName: "shippingbox", title: "No Packages", message: "Install one")
        XCTAssertEqual(emptyHost.model.combinedAccessibilityLabel, "No Packages. Install one")
        XCTAssertNotNil(emptyHost.viewController.view)

        let loadingHost = BPLoadingHost()
        XCTAssertNotNil(loadingHost.viewController.view)

        let disabledHost = BPDisabledHost()
        disabledHost.update(title: "Missing", message: "Install Homebrew", retryEnabled: true, checking: false)
        XCTAssertNotNil(disabledHost.viewController.view)

        let consoleHost = BPConsoleToolHost(
            textView: NSTextView(),
            title: "Homebrew Doctor",
            subtitle: nil,
            runButtonTitle: "Run Doctor",
            clearButtonTitle: "Clear Log")
        consoleHost.isRunning = true
        XCTAssertTrue(consoleHost.isRunning)
        XCTAssertNotNil(consoleHost.viewController.view)

        let servicesHost = BPServicesHost(tableScrollView: NSView(), detailsScrollView: NSView())
        servicesHost.update(
            startEnabled: true,
            stopEnabled: false,
            restartEnabled: true,
            revealEnabled: true,
            logsEnabled: false,
            copyEnabled: true)
        XCTAssertNotNil(servicesHost.viewController.view)

        let autoremoveHost = BPAutoremoveHost(outputTextView: NSTextView())
        autoremoveHost.update(
            statusText: "Review 2 unused dependencies before removal.",
            removeEnabled: true,
            cancelTitle: "Close",
            cancelEnabled: true,
            busy: false)
        XCTAssertNotNil(autoremoveHost.viewController.view)

        let bundleHost = BPBundleOperationHost(importTextView: NSTextView())
        bundleHost.configureImport(statusText: "Importing", actionTitle: "Cancel", actionEnabled: true, running: true)
        bundleHost.configureExport(
            statusText: "Export Successful",
            detailText: nil,
            actionTitle: "Close",
            actionEnabled: true,
            running: false,
            finished: true,
            succeeded: true)
        XCTAssertNotNil(bundleHost.viewController.view)

        let optionsHost = BPFormulaOptionsHost()
        optionsHost.configure(
            formulaName: "ffmpeg",
            optionNames: ["--with-x265", "--HEAD"],
            optionExplanations: ["Enable x265", "Install HEAD"])
        XCTAssertEqual(optionsHost.selectedOptionNames, [])
        XCTAssertNotNil(optionsHost.viewController.view)

        let installHost = BPInstallationHost(recordTextView: NSTextView())
        installHost.update(
            windowTitle: "Installing Formula:",
            formulaNames: "wget",
            running: true,
            okEnabled: false,
            cancelEnabled: true)
        XCTAssertNotNil(installHost.viewController.view)
    }

    func testSidebarStateTapInputStateCleanupPreviewStateAndSnapshotDependencies() {
        let snapshot = BPSelectedFormulaSnapshot(
            name: "ffmpeg",
            cask: false,
            isInstalled: true,
            isPinned: false,
            installPath: "/opt/homebrew/Cellar/ffmpeg/7.1",
            latestVersion: "7.1",
            dependencies: "dav1d, lame, x264, x265",
            conflicts: "ffmpeg@6, libav",
            shortDescription: "Play, record, convert, and stream audio and video"
        )
        XCTAssertEqual(snapshot.dependencyNames, ["dav1d", "lame", "x264", "x265"])
        XCTAssertEqual(snapshot.conflictNames, ["ffmpeg@6", "libav"])

        let row1 = BPSidebarRowState(
            rowIndex: 1,
            title: "Installed",
            groupTitle: "Formulae",
            symbolName: "checkmark.square",
            badgeCount: 42,
            accessibilityIdentifier: "sidebar.formulae.installed",
            accessibilityLabel: "Formulae, Installed, 42 items"
        )
        let row2 = BPSidebarRowState(
            rowIndex: 2,
            title: "Outdated",
            groupTitle: "Formulae",
            symbolName: "clock.arrow.circlepath",
            badgeCount: 3,
            accessibilityIdentifier: "sidebar.formulae.outdated",
            accessibilityLabel: "Formulae, Outdated, 3 items"
        )
        let section = BPSidebarSectionState(rowIndex: 0, title: "Formulae", rows: [row1, row2])
        let sidebarState = BPSidebarState(sections: [section], selectedRowIndex: 2)
        XCTAssertEqual(sidebarState.allRows.count, 2)
        XCTAssertEqual(sidebarState.selectedRow?.accessibilityIdentifier, "sidebar.formulae.outdated")
        XCTAssertEqual(sidebarState.badgeCount(forRowIndex: 1), 42)
        XCTAssertEqual(sidebarState.badgeCount(forRowIndex: 99), -1)

        var tapState = BPTapInputState()
        XCTAssertFalse(tapState.isValidFormat)
        tapState.repositoryName = "invalid-tap-without-slash"
        XCTAssertFalse(tapState.isValidFormat)
        tapState.repositoryName = "  homebrew/cask-fonts  "
        XCTAssertTrue(tapState.isValidFormat)
        XCTAssertEqual(tapState.trimmedName, "homebrew/cask-fonts")

        let cleanupState = BPCleanupPreviewState(
            itemCount: 3,
            reclaimableBytes: 51_589_939,
            formattedByteCount: "49.2 MB",
            samplePaths: ["/Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz"]
        )
        XCTAssertEqual(cleanupState.itemCount, 3)
        XCTAssertEqual(cleanupState.formattedByteCount, "49.2 MB")
    }

    @MainActor
    func testConsoleAndOperationSheetLogFilterDiagnosticBadgesAndCopyOutput() {
        let doctorText = NSTextView()
        let consoleHost = BPConsoleToolHost(
            textView: doctorText,
            title: "Homebrew Doctor",
            subtitle: nil,
            runButtonTitle: "Run Doctor",
            clearButtonTitle: "Clear Log"
        )
        XCTAssertEqual(consoleHost.diagnosticSeverityRawValue, BPConsoleDiagnosticSeverity.idle.rawValue)
        XCTAssertEqual(consoleHost.totalLineCount, 0)

        doctorText.string = "Your system is ready to brew.\n"
        consoleHost.syncLogFromTextView()
        XCTAssertEqual(consoleHost.diagnosticSeverityRawValue, BPConsoleDiagnosticSeverity.healthy.rawValue)
        XCTAssertEqual(consoleHost.warningCount, 0)
        XCTAssertEqual(consoleHost.errorCount, 0)
        XCTAssertEqual(consoleHost.totalLineCount, 1)

        doctorText.string = """
        Warning: Unbrewed dylibs were found in /usr/local/lib.
        If you didn't put them there on purpose they could cause problems.
        Warning: You have unlinked kegs in your Cellar.
        """
        consoleHost.syncLogFromTextView()
        XCTAssertEqual(consoleHost.diagnosticSeverityRawValue, BPConsoleDiagnosticSeverity.warnings.rawValue)
        XCTAssertEqual(consoleHost.warningCount, 2)
        XCTAssertEqual(consoleHost.totalLineCount, 3)

        consoleHost.filterQuery = "unlinked"
        XCTAssertEqual(consoleHost.matchingLineCount, 1)
        let copiedConsole = consoleHost.copyOutputToPasteboard()
        XCTAssertEqual(copiedConsole, "Warning: You have unlinked kegs in your Cellar.")
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), copiedConsole)

        doctorText.string = "Error: Failed to download bottle for wget\n"
        consoleHost.filterQuery = ""
        consoleHost.syncLogFromTextView()
        XCTAssertEqual(consoleHost.diagnosticSeverityRawValue, BPConsoleDiagnosticSeverity.errors.rawValue)
        XCTAssertEqual(consoleHost.errorCount, 1)

        let installText = NSTextView()
        installText.string = "==> Downloading wget\n==> Pouring wget--1.25.0.bottle.tar.gz\n🍺  /opt/homebrew/Cellar/wget/1.25.0\n"
        let installHost = BPInstallationHost(recordTextView: installText)
        installHost.syncLogFromTextView()
        XCTAssertEqual(installHost.totalLineCount, 3)
        installHost.filterQuery = "Cellar"
        XCTAssertEqual(installHost.matchingLineCount, 1)
        let copiedInstall = installHost.copyOutputToPasteboard()
        XCTAssertEqual(copiedInstall, "🍺  /opt/homebrew/Cellar/wget/1.25.0")

        let bundleText = NSTextView()
        bundleText.string = "Using homebrew/core\nInstalling ripgrep\nHomebrew Bundle complete!\n"
        let bundleHost = BPBundleOperationHost(importTextView: bundleText)
        bundleHost.syncLogFromTextView()
        XCTAssertEqual(bundleHost.totalLineCount, 3)
        bundleHost.filterQuery = "ripgrep"
        XCTAssertEqual(bundleHost.matchingLineCount, 1)
        XCTAssertEqual(bundleHost.copyOutputToPasteboard(), "Installing ripgrep")

        let autoremoveText = NSTextView()
        autoremoveText.string = "==> Would uninstall 2 unneeded formulae:\nlibnghttp2\nca-certificates\n"
        let autoremoveHost = BPAutoremoveHost(outputTextView: autoremoveText)
        autoremoveHost.candidateCount = 2
        autoremoveHost.syncLogFromTextView()
        XCTAssertEqual(autoremoveHost.candidateCount, 2)
        XCTAssertEqual(autoremoveHost.totalLineCount, 3)
        autoremoveHost.filterQuery = "libnghttp2"
        XCTAssertEqual(autoremoveHost.matchingLineCount, 1)
        XCTAssertEqual(autoremoveHost.copyOutputToPasteboard(), "libnghttp2")
    }

    @MainActor
    func testServicesStateBrewfileReviewFilterAndFormulaOptionsSearch() {
        // 1. BPServicesHost & BPServicesState
        let servicesHost = BPServicesHost(tableScrollView: NSView(), detailsScrollView: NSView())
        servicesHost.syncCounts(running: 2, stopped: 3, error: 1)
        XCTAssertEqual(servicesHost.runningCount, 2)
        XCTAssertEqual(servicesHost.stoppedCount, 3)
        XCTAssertEqual(servicesHost.errorCount, 1)
        XCTAssertEqual(servicesHost.totalCount, 6)

        servicesHost.syncPaths(serviceFile: "/opt/homebrew/opt/postgresql@16/homebrew.mxcl.postgresql@16.plist",
                               logFile: "/opt/homebrew/var/log/postgresql@16.log")
        XCTAssertEqual(servicesHost.serviceFilePath, "/opt/homebrew/opt/postgresql@16/homebrew.mxcl.postgresql@16.plist")
        XCTAssertEqual(servicesHost.logFilePath, "/opt/homebrew/var/log/postgresql@16.log")
        XCTAssertEqual(servicesHost.copyServiceFilePathToPasteboard(),
                       "/opt/homebrew/opt/postgresql@16/homebrew.mxcl.postgresql@16.plist")
        XCTAssertEqual(servicesHost.copyLogPathToPasteboard(),
                       "/opt/homebrew/var/log/postgresql@16.log")

        servicesHost.onFilterChanged = {
            // @Sendable callback invoked on filter or query change
        }
        servicesHost.statusFilterRawValue = BPServiceStatusFilter.running.rawValue
        servicesHost.filterQuery = "postgres"
        XCTAssertEqual(servicesHost.statusFilterRawValue, BPServiceStatusFilter.running.rawValue)
        XCTAssertEqual(servicesHost.filterQuery, "postgres")

        // 2. BPBrewfileReviewHost & BPBrewfileReviewState
        let entriesView = NSTextView()
        entriesView.string = """
        Taps (1)
          • homebrew/core — Installed
        Formulae (2)
          • wget — Installed
          • ripgrep — Missing
        Casks (1)
          • firefox — Missing
        """
        let reviewHost = BPBrewfileReviewHost(
            entriesTextView: entriesView,
            fileName: "Brewfile",
            installedCount: 2,
            missingCount: 2,
            notCheckedCount: 0,
            formulaCount: 2,
            caskCount: 1,
            tapCount: 1,
            otherCount: 0,
            canInstall: true,
            summaryText: entriesView.string
        )
        XCTAssertEqual(reviewHost.matchingEntryCount, 4)

        reviewHost.statusFilterRawValue = BPBrewfileEntryFilter.missing.rawValue
        XCTAssertEqual(reviewHost.matchingEntryCount, 2)
        reviewHost.filterQuery = "firefox"
        XCTAssertEqual(reviewHost.matchingEntryCount, 1)
        XCTAssertEqual(reviewHost.copySummaryToPasteboard(), "  • firefox — Missing")

        // 3. BPFormulaOptionsHost & BPFormulaOptionsSheetState
        let optionsHost = BPFormulaOptionsHost()
        optionsHost.configure(
            formulaName: "ffmpeg",
            optionNames: ["--with-x265", "--with-fdk-aac", "--HEAD"],
            optionExplanations: ["Enable x265", "Enable Fraunhofer FDK AAC", "Build from git HEAD"]
        )
        XCTAssertEqual(optionsHost.filteredOptionCount, 3)
        XCTAssertEqual(optionsHost.appliedOptionCount, 0)

        optionsHost.setApplied(true, forOptionNamed: "--with-x265")
        optionsHost.setApplied(true, forOptionNamed: "--HEAD")
        XCTAssertEqual(optionsHost.appliedOptionCount, 2)

        optionsHost.filterQuery = "aac"
        XCTAssertEqual(optionsHost.filteredOptionCount, 1)

        optionsHost.clearAllAppliedOptions()
        XCTAssertEqual(optionsHost.appliedOptionCount, 0)
        XCTAssertEqual(optionsHost.selectedOptionNames, [])
    }

    @MainActor
    func testSwift6CoreModelsViewsAndControllers() {
        let preview = BPAutoremovePreview.preview(
            withOutput: "==> Would autoremove 2 unneeded formulae:\nlibpng\njpeg\n",
            succeeded: true
        )
        XCTAssertTrue(preview.valid)
        XCTAssertEqual(preview.names, ["libpng", "jpeg"])

        let cleanup = BPCleanupPreview.preview(
            fromOutput: "Would remove: /opt/homebrew/Cellar/wget/1.0 (1.0MB)\n==> This operation would free approximately 2.0MB of disk space.\n"
        )
        XCTAssertFalse(cleanup.empty)
        XCTAssertEqual(cleanup.itemCount, 1)
        XCTAssertEqual(cleanup.reclaimableBytes, 2 * 1024 * 1024)

        let err = BPBrewError.error(forExitStatus: 1, output: "Error: formula not found\n")
        XCTAssertNotNil(err)
        XCTAssertEqual(err?.code, 2)

        XCTAssertTrue(BPBrewfile.isBrewfileURL(URL(fileURLWithPath: "/tmp/work.Brewfile")))
        let plan = BPBrewfilePlan.plan(withString: "brew 'git'\ncask 'firefox'\n", inventories: ["brew": ["git"], "cask": []])
        XCTAssertTrue(plan.canInstall)
        XCTAssertEqual(plan.entries.count, 2)

        let services = BPService.services(fromJSONString: "[{\"name\":\"redis\",\"status\":\"started\",\"pid\":42,\"user\":\"admin\"}]")
        XCTAssertEqual(services.count, 1)
        XCTAssertEqual(services.first?.status, .started)

        let details = BPServiceDetails.details(
            forName: "redis",
            output: "[{\"name\":\"redis\",\"status\":\"started\",\"pid\":42,\"file\":\"/opt/redis.plist\"}]",
            succeeded: true
        )
        XCTAssertTrue(details.available)
        XCTAssertEqual(details.serviceFile, "/opt/redis.plist")

        XCTAssertNotNil(BPStyle.defaultFixedWidthFont())
        XCTAssertNotNil(BPStyle.toolbarImageForInstall())

        let dockMenu = BPDockMenu.dockMenu(withTarget: nil, enabled: true)
        XCTAssertEqual(dockMenu.items.count, 3)

        let toolbar = BPToolbar(identifier: NSToolbar.Identifier("Swift6Test"))
        XCTAssertFalse(toolbar.allowsUserCustomization)
        toolbar.configure(for: .install)
        XCTAssertEqual(toolbar.currentMode, .install)

        let aboutWC = DCOAboutWindowController()
        XCTAssertNotNil(aboutWC.window)
        XCTAssertNotNil(aboutWC.aboutHost)
    }

    @MainActor
    func testSwift6Wave7OperationsControllersAndDataSources() {
        // BPFormulaeTableActions
        let toolbarMode = BPFormulaeTableActions.toolbarMode(
            forSidebarRow: Int(FormulaeSideBarItem.outdated.rawValue),
            selectedCount: 2,
            selectedFormulaStatus: 1
        )
        XCTAssertEqual(toolbarMode, .updateMany)
        XCTAssertFalse(BPFormulaeTableActions.shouldShowFormulaInfo(forSidebarRow: Int(FormulaeSideBarItem.repositories.rawValue)))
        XCTAssertTrue(BPFormulaeTableActions.shouldShowFormulaInfo(forSidebarRow: Int(FormulaeSideBarItem.installed.rawValue)))

        // BPPackageOperationPresenter
        let tapAlert = BPPackageOperationPresenter.tapInputAlert()
        let tapHost = BPPackageOperationPresenter.tapInputHost(for: tapAlert)
        XCTAssertNotNil(tapHost)

        // BPSideBarController
        let sidebarController = BPSideBarController()
        XCTAssertEqual(sidebarController.selectableRowAccessibilityIdentifiers().count, 13)
        XCTAssertEqual(BPSideBarController.restorableRow(from: 99, rowCount: 16), .installed)

        // BPTask
        let task = BPTask(path: "/bin/sh", arguments: ["-c", "printf 'swift6-task'"])
        XCTAssertEqual(task.execute(), 0)
        XCTAssertEqual(task.output, "swift6-task")

        // BPWindow
        let window = BPWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: true
        )
        XCTAssertTrue(window.titlebarAppearsTransparent)

        // BPDoctorViewController & BPUpdateViewController
        let doctorVC = BPDoctorViewController()
        _ = doctorVC.view
        XCTAssertNotNil(doctorVC.consoleHost)
        XCTAssertNotNil(doctorVC.doctorTextView)

        let updateVC = BPUpdateViewController()
        _ = updateVC.view
        XCTAssertNotNil(updateVC.consoleHost)
        XCTAssertNotNil(updateVC.updateTextView)

        // BPFormulaPopoverViewController & BPSelectedFormulaViewController
        let popoverVC = BPFormulaPopoverViewController()
        _ = popoverVC.view
        XCTAssertEqual(popoverVC.infoType, .general)

        let selectedVC = BPSelectedFormulaViewController(nibName: nil, bundle: nil)
        _ = selectedVC.view
        XCTAssertNotNil(selectedVC.inspectorHost)

        // BPFormulaOptionsWindowController, BPPreferencesWindowController, BPBundleWindowController
        let optionsWC = BPFormulaOptionsWindowController(windowNibName: "BPFormulaOptionsWindow")
        _ = optionsWC.window
        XCTAssertNotNil(optionsWC.optionsHost)

        let prefsWC = BPPreferencesWindowController()
        XCTAssertNotNil(prefsWC.window)
        XCTAssertNotNil(prefsWC.preferencesHost)

        let bundleWC = BPBundleWindowController.createWindow()
        _ = bundleWC.window
        bundleWC.windowDidLoad()
        XCTAssertNotNil(bundleWC.bundleHost)
    }

}
