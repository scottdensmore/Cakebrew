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

}
