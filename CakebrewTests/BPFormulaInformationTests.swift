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

}
