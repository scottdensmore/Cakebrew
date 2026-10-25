//
//  BPHomebrewManagerTests.swift
//  CakebrewTests
//
//  Tests for BPHomebrewManager's pure status logic: statusForFormula: derives a
//  formula's state from the installed/outdated lists, matching by installedName
//  (so tap-qualified and short names compare equal).
//

import XCTest

/// The cask list parsers set this flag in production; fixtures set it directly.
private enum BPMockCaskFlag {
    static func markAsCasks(_ formulae: [BPFormula]) {
        for formula in formulae {
            formula.cask = true
        }
    }
}

final class BPHomebrewManagerTests: XCTestCase, BPHomebrewManagerDelegate, @unchecked Sendable {
    var manager: BPHomebrewManager!
    var searchCompletion: (() -> Void)?

    override func setUp() {
        super.setUp()
        // BPHomebrewManager is a singleton. Each test sets the lists it needs,
        // and setUp/tearDown reset them so there is no state bleed between tests.
        manager = BPHomebrewManager.sharedManager()
        manager.delegate = self
        manager.installedFormulae = []
        manager.outdatedFormulae = []
        manager.allFormulae = []
        manager.searchFormulae = []
        manager.pinnedFormulae = []
        manager.publishPinnedCasks([], generation: manager.currentReloadGeneration)
        manager.installedCasks = []
        manager.outdatedCasks = []
    }

    override func tearDown() {
        manager.installedFormulae = []
        manager.outdatedFormulae = []
        manager.allFormulae = []
        manager.searchFormulae = []
        manager.pinnedFormulae = []
        manager.publishPinnedCasks([], generation: manager.currentReloadGeneration)
        manager.installedCasks = []
        manager.outdatedCasks = []
        manager = nil
        super.tearDown()
    }

    /// Runs a search and waits for it to publish. The scan moved off the main
    /// thread (8.5k names per keystroke was blocking it), so results arrive on a
    /// later turn of the run loop rather than before the call returns.
    private func search(_ query: String) {
        manager.updateSearch(withName: query)

        let deadline = Date(timeIntervalSinceNow: 5.0)
        var published = false
        // The delegate callback is the completion signal; polling searchFormulae
        // cannot distinguish "not yet" from "no matches".
        searchCompletion = { published = true }
        while !published && deadline.timeIntervalSinceNow > 0 {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        searchCompletion = nil
        XCTAssertTrue(published, "the search for '\(query)' never published")
    }

    func testUpdateSearchFiltersAllFormulaeByName() {
        let wget = BPFormula.formula(withName: "wget")
        let git = BPFormula.formula(withName: "git")
        let wgetpaste = BPFormula.formula(withName: "wgetpaste")
        manager.allFormulae = [wget, git, wgetpaste]

        search("wget")

        let results = manager.searchFormulae ?? []
        XCTAssertEqual(results.count, 2, "wget and wgetpaste contain 'wget'")
        XCTAssertTrue(results.contains(wget))
        XCTAssertTrue(results.contains(wgetpaste))
        XCTAssertFalse(results.contains(git))
    }

    func testUpdateSearchIsCaseInsensitive() {
        let node = BPFormula.formula(withName: "node")
        manager.allFormulae = [node]

        search("NODE")

        XCTAssertEqual(manager.searchFormulae, [node])
    }

    func testUpdateSearchWithNoMatchesIsEmpty() {
        manager.allFormulae = [BPFormula.formula(withName: "wget")]

        search("zzznope")

        XCTAssertEqual(manager.searchFormulae?.count, 0)
    }

    func testStatusIsNotInstalledWhenAbsent() {
        manager.installedFormulae = [BPFormula.formula(withName: "git")]
        XCTAssertEqual(manager.status(forFormula: BPFormula.formula(withName: "wget")), .notInstalled)
    }

    func testStatusIsInstalledWhenPresentAndNotOutdated() {
        manager.installedFormulae = [BPFormula.formula(withName: "git")]
        manager.outdatedFormulae = []
        XCTAssertEqual(manager.status(forFormula: BPFormula.formula(withName: "git")), .installed)
    }

    func testStatusIsOutdatedWhenPresentInBoth() {
        manager.installedFormulae = [BPFormula.formula(withName: "git")]
        manager.outdatedFormulae = [BPFormula.formula(withName: "git")]
        XCTAssertEqual(manager.status(forFormula: BPFormula.formula(withName: "git")), .outdated)
    }

    func testStatusMatchesByShortNameAcrossTaps() {
        // Installed under the short name; a tap-qualified query still matches via installedName.
        manager.installedFormulae = [BPFormula.formula(withName: "foo")]
        XCTAssertEqual(manager.status(forFormula: BPFormula.formula(withName: "homebrew/core/foo")), .installed)
    }

    func testStatusIsNotInstalledWhenOnlyInOutdatedList() {
        // statusForFormula gates on the installed list first, so a formula that is
        // only in the outdated list (but not installed) is reported as not installed.
        manager.installedFormulae = []
        manager.outdatedFormulae = [BPFormula.formula(withName: "git")]
        XCTAssertEqual(manager.status(forFormula: BPFormula.formula(withName: "git")), .notInstalled)
    }

    // MARK: - cask status (statusForFormula: reads the cask lists)

    private func cask(withName name: String) -> BPFormula {
        let cask = BPFormula.formula(withName: name)
        cask.cask = true
        return cask
    }

    func testStatusForCaskInstalledWhenInInstalledCasks() {
        manager.installedCasks = [cask(withName: "firefox")]
        XCTAssertEqual(manager.status(forFormula: cask(withName: "firefox")), .installed)
    }

    func testStatusForCaskOutdatedWhenInBothCaskLists() {
        manager.installedCasks = [cask(withName: "firefox")]
        manager.outdatedCasks = [cask(withName: "firefox")]
        XCTAssertEqual(manager.status(forFormula: cask(withName: "firefox")), .outdated)
    }

    func testStatusForCaskNotInstalledWhenAbsentFromCaskLists() {
        manager.installedCasks = [cask(withName: "chrome")]
        XCTAssertEqual(manager.status(forFormula: cask(withName: "firefox")), .notInstalled)
    }

    func testStatusForCaskIgnoresFormulaListsOnNameCollision() {
        // A cask must not read the formula lists even when a formula shares its name.
        manager.installedFormulae = [BPFormula.formula(withName: "firefox")]
        XCTAssertEqual(manager.status(forFormula: cask(withName: "firefox")), .notInstalled)
    }

    // MARK: - pinned state (isFormulaPinned:)

    func testIsFormulaPinnedReturnsYesForPinnedFormula() {
        let git = BPFormula.formula(withName: "git")
        manager.pinnedFormulae = [git]

        XCTAssertTrue(manager.isFormulaPinned(git))
    }

    func testIsFormulaPinnedReturnsNoForUnpinnedFormula() {
        manager.pinnedFormulae = [BPFormula.formula(withName: "git")]

        XCTAssertFalse(manager.isFormulaPinned(BPFormula.formula(withName: "wget")))
    }

    func testIsFormulaPinnedIsFalseWhenNothingPinned() {
        manager.pinnedFormulae = []
        XCTAssertFalse(manager.isFormulaPinned(BPFormula.formula(withName: "git")))
    }

    func testIsFormulaPinnedMatchesByShortNameAcrossTaps() {
        // `brew list --pinned` may emit tap-qualified names; matching uses installedName.
        manager.pinnedFormulae = [BPFormula.formula(withName: "homebrew/core/git")]
        XCTAssertTrue(manager.isFormulaPinned(BPFormula.formula(withName: "git")))
    }

    func testIsFormulaPinnedReturnsNoForSameNamedCask() {
        manager.pinnedFormulae = [BPFormula.formula(withName: "shared")]
        XCTAssertTrue(manager.isFormulaPinned(BPFormula.formula(withName: "shared")))
        XCTAssertFalse(
            manager.isFormulaPinned(cask(withName: "shared")),
            "A pinned formula must never mark a same-named cask as pinned"
        )
    }

    func testCaskPinsStayDistinctFromFormulaPinsAndAppearInPinnedList() {
        let pinned = cask(withName: "cakebrew/history-example/shared")
        manager.publishPinnedCasks([pinned], generation: manager.currentReloadGeneration)
        XCTAssertTrue(manager.isFormulaPinned(cask(withName: "shared")))
        XCTAssertFalse(manager.isFormulaPinned(BPFormula.formula(withName: "shared")))
        XCTAssertTrue(manager.pinnedFormulae?.contains { $0.cask && $0.installedName() == "shared" } == true)
        manager.publishPinnedCasks([], generation: manager.currentReloadGeneration)
        XCTAssertFalse(manager.isFormulaPinned(pinned))
    }

    // MARK: - search covers casks

    private func names(of formulae: [BPFormula]) -> [String] {
        formulae.compactMap(\.name)
    }

    func testSearchMatchesCasksAsWellAsFormulae() {
        // Typing "chrome" returned nothing even though the cask browse lists show
        // it: the matcher only ever walked allFormulae.
        let formulae = [BPFormula.formula(withName: "wget")]
        let casks = [BPFormula.formula(withName: "mockchrome")]
        BPMockCaskFlag.markAsCasks(casks)

        let matches = BPHomebrewManager.formulae(formulae, casks: casks, matchingQuery: "chrome")

        XCTAssertEqual(names(of: matches), ["mockchrome"])
    }

    func testAMatchedCaskStaysACask() {
        // statusForFormula:, the detail pane and operation dispatch all branch on
        // this flag, so a search hit that loses it would be treated as a formula.
        let casks = [BPFormula.formula(withName: "mockchrome")]
        BPMockCaskFlag.markAsCasks(casks)

        let matches = BPHomebrewManager.formulae([], casks: casks, matchingQuery: "chrome")

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches.first?.cask, true, "a matched cask must still dispatch as --cask")
    }

    func testSearchIsCaseInsensitiveAcrossBothNamespaces() {
        let formulae = [BPFormula.formula(withName: "WGet")]
        let casks = [BPFormula.formula(withName: "MockChrome")]
        BPMockCaskFlag.markAsCasks(casks)

        XCTAssertEqual(BPHomebrewManager.formulae(formulae, casks: casks, matchingQuery: "wget").count, 1)
        XCTAssertEqual(BPHomebrewManager.formulae(formulae, casks: casks, matchingQuery: "chrome").count, 1)
    }

    func testFormulaeComeBeforeCasksSoTheNamespacesAreNotInterleaved() {
        let formulae = [BPFormula.formula(withName: "zzz-formula")]
        let casks = [BPFormula.formula(withName: "aaa-cask")]
        BPMockCaskFlag.markAsCasks(casks)

        let matches = BPHomebrewManager.formulae(formulae, casks: casks, matchingQuery: "a")
        XCTAssertEqual(names(of: matches), ["zzz-formula", "aaa-cask"])
    }

    func testAnEmptyQueryMatchesNothing() {
        // Clearing the field ends the search; it should not dump the whole catalog.
        let formulae = [BPFormula.formula(withName: "wget")]
        XCTAssertEqual(BPHomebrewManager.formulae(formulae, casks: [], matchingQuery: "").count, 0)
        XCTAssertEqual(BPHomebrewManager.formulae(formulae, casks: [], matchingQuery: nil).count, 0)
    }

    // MARK: - late results

    func testResultsForASupersededQueryAreDiscarded() {
        // Scanning 8.5k names is slow enough that a slower earlier query can land
        // after a faster later one and overwrite it.
        XCTAssertTrue(BPHomebrewManager.shouldPublishResults(forQuery: "chrome", currentQuery: "chrome"))
        XCTAssertFalse(
            BPHomebrewManager.shouldPublishResults(forQuery: "chr", currentQuery: "chrome"),
            "a result for an earlier keystroke must not replace the current one"
        )
        XCTAssertFalse(
            BPHomebrewManager.shouldPublishResults(forQuery: "chrome", currentQuery: nil),
            "the search was cancelled while this was running"
        )
    }

    // MARK: - BPHomebrewManagerDelegate

    func homebrewManager(_ manager: BPHomebrewManager, didUpdateSearchResults searchResults: [Any]?) {
        searchCompletion?()
    }

    func homebrewManagerFinishedUpdating(_ manager: BPHomebrewManager) {}
    func homebrewManager(_ manager: BPHomebrewManager, shouldDisplayNoBrewMessage yesOrNo: Bool) {}

    // MARK: - reload coalescing

    func testASecondReloadRequestDoesNotStartASecondPipeline() {
        // Four callers can fire a reload — launch, the background timer,
        // post-operation, and unlock-after-no-brew — and the timer only checks
        // whether a brew *operation* is running, not whether a reload already is.
        XCTAssertTrue(BPHomebrewManager.shouldStartReload(whenInFlight: false))
        XCTAssertFalse(
            BPHomebrewManager.shouldStartReload(whenInFlight: true),
            "a concurrent request should coalesce, not start a second pipeline"
        )
    }

    func testOnlyTheNewestPipelineMayPublish() {
        // Whichever pipeline finished last used to win the property assignments,
        // so a slower older snapshot could clobber a newer one.
        XCTAssertTrue(BPHomebrewManager.shouldPublishReloadGeneration(4, current: 4))
        XCTAssertFalse(
            BPHomebrewManager.shouldPublishReloadGeneration(3, current: 4),
            "a superseded snapshot must be discarded, not published"
        )
    }

    func testUpdatingListsRefreshesStatusAndPinLookupSetsImmediately() {
        let git = BPFormula.formula(withName: "git", andVersion: "2.40.0")
        let tapGit = BPFormula.formula(withName: "myorg/tap/git")

        manager.installedFormulae = [git]
        XCTAssertEqual(manager.status(forFormula: tapGit), .installed)

        manager.outdatedFormulae = [git]
        XCTAssertEqual(manager.status(forFormula: tapGit), .outdated)

        manager.pinnedFormulae = [git]
        XCTAssertTrue(manager.isFormulaPinned(tapGit))

        manager.outdatedFormulae = []
        manager.installedFormulae = []
        manager.pinnedFormulae = []
        XCTAssertEqual(manager.status(forFormula: tapGit), .notInstalled)
        XCTAssertFalse(manager.isFormulaPinned(tapGit))
    }

    func testTenThousandCatalogStatusAndPinLookupsCompleteUnderFiftyMilliseconds() {
        var catalog: [BPFormula] = []
        catalog.reserveCapacity(10000)
        var installed: [BPFormula] = []
        installed.reserveCapacity(500)
        var outdated: [BPFormula] = []
        outdated.reserveCapacity(50)
        var pinned: [BPFormula] = []
        pinned.reserveCapacity(20)

        for i in 0..<10000 {
            let name = String(format: "pkg-%05lu", UInt(i))
            let formula = BPFormula.formula(withName: name, andVersion: "1.0.0")
            catalog.append(formula)
            if i % 20 == 0 {
                installed.append(formula)
            }
            if i % 200 == 0 {
                outdated.append(formula)
            }
            if i % 500 == 0 {
                pinned.append(formula)
            }
        }

        manager.installedFormulae = installed
        manager.outdatedFormulae = outdated
        manager.pinnedFormulae = pinned

        let start = CFAbsoluteTimeGetCurrent()
        var installedCount: UInt = 0
        var outdatedCount: UInt = 0
        var pinnedCount: UInt = 0
        for formula in catalog {
            let status = manager.status(forFormula: formula)
            if status == .installed { installedCount += 1 }
            if status == .outdated { outdatedCount += 1 }
            if manager.isFormulaPinned(formula) { pinnedCount += 1 }
        }
        let elapsedMs = (CFAbsoluteTimeGetCurrent() - start) * 1000.0

        XCTAssertEqual(installedCount, 450)
        XCTAssertEqual(outdatedCount, 50)
        XCTAssertEqual(pinnedCount, 20)
        XCTAssertLessThan(elapsedMs, 50.0, "10,000 status + pin lookups must be O(1) and complete well under 50 ms")
    }
}
