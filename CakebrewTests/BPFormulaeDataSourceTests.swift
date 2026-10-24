import XCTest
import AppKit
import Foundation

@MainActor
final class BPFormulaeDataSourceTests: XCTestCase, @unchecked Sendable {
    private static let kColumnIdentifierName = "Name"
    private static let kColumnIdentifierVersion = "Version"
    private static let kColumnIdentifierStatus = "Status"

    private var manager: BPHomebrewManager!
    private var tableView: NSTableView!

    override func setUp() {
        super.setUp()
        MainActor.assumeIsolated {
            manager = BPHomebrewManager.sharedManager()
            manager.installedFormulae = []
            manager.allFormulae = []
            tableView = NSTableView()
        }
    }

    override func tearDown() {
        MainActor.assumeIsolated {
            manager.installedFormulae = []
            manager.allFormulae = []
            manager = nil
            tableView = nil
        }
        super.tearDown()
    }

    func testInstalledModeReflectsInstalledList() {
        let git = BPFormula.formula(withName: "git")
        let wget = BPFormula.formula(withName: "wget")
        manager.installedFormulae = [git, wget]

        let dataSource = BPFormulaeDataSource(mode: BPListMode.installed.rawValue)

        XCTAssertEqual(dataSource.numberOfRows(in: tableView), 2)
        XCTAssertEqual(dataSource.formula(at: 0) as? BPFormula, git)
        XCTAssertEqual(dataSource.formula(at: 1) as? BPFormula, wget)
    }

    func testFormulaAtIndexOutOfBoundsReturnsNil() {
        manager.installedFormulae = [BPFormula.formula(withName: "git")]
        let dataSource = BPFormulaeDataSource(mode: BPListMode.installed.rawValue)

        XCTAssertNil(dataSource.formula(at: 5))
        XCTAssertNil(dataSource.formula(at: -1))
    }

    func testFormulasAtIndexSetReturnsSelectedFormulae() {
        let a = BPFormula.formula(withName: "a")
        let b = BPFormula.formula(withName: "b")
        let c = BPFormula.formula(withName: "c")
        manager.allFormulae = [a, b, c]

        let dataSource = BPFormulaeDataSource(mode: BPListMode.all.rawValue)

        var indexes = IndexSet()
        indexes.insert(0)
        indexes.insert(2)

        XCTAssertEqual(dataSource.formulas(at: indexes) as? [BPFormula], [a, c])
    }

    func testFormulasAtIndexSetOutOfRangeReturnsNil() {
        manager.installedFormulae = [BPFormula.formula(withName: "git")]
        let dataSource = BPFormulaeDataSource(mode: BPListMode.installed.rawValue)

        XCTAssertNil(dataSource.formulas(at: IndexSet(integer: 5)))
    }

    func testChangingModeRefreshesBackingArray() {
        manager.installedFormulae = [BPFormula.formula(withName: "git")]
        manager.allFormulae = [BPFormula.formula(withName: "a"), BPFormula.formula(withName: "b")]

        let dataSource = BPFormulaeDataSource(mode: BPListMode.installed.rawValue)
        XCTAssertEqual(dataSource.numberOfRows(in: tableView), 1)

        dataSource.mode = BPListMode.all.rawValue
        XCTAssertEqual(dataSource.numberOfRows(in: tableView), 2)
    }

    // MARK: - name cell value (pin badge)

    func testNameCellValueForUnpinnedFormulaIsPlainName() {
        let git = BPFormula.formula(withName: "git")
        let value = BPFormulaeDataSource.nameCellValue(forFormula: git, pinned: false)

        XCTAssertTrue(value is NSString, "unpinned name is a plain string")
        XCTAssertEqual(value as? String, "git")
    }

    func testNameCellValueForPinnedFormulaIsAttributedStartingWithName() {
        let git = BPFormula.formula(withName: "git")
        let value = BPFormulaeDataSource.nameCellValue(forFormula: git, pinned: true)

        XCTAssertTrue(value is NSAttributedString, "pinned name carries a pin badge")
        XCTAssertTrue(
            (value as? NSAttributedString)?.string.hasPrefix("git") ?? false,
            "the pinned name cell must still start with the formula name"
        )
    }

    // MARK: - finding a row by name (restoring selection after a reload)

    func testIndexOfFormulaNamedFindsTheRow() {
        let manager = BPHomebrewManager.sharedManager()
        manager.installedFormulae = [
            BPFormula.formula(withName: "wget"),
            BPFormula.formula(withName: "git"),
            BPFormula.formula(withName: "curl")
        ]

        let dataSource = BPFormulaeDataSource(mode: BPListMode.installed.rawValue)
        dataSource.refreshBackingArray()

        XCTAssertEqual(dataSource.indexOfFormula(named: "wget"), 0)
        XCTAssertEqual(dataSource.indexOfFormula(named: "git"), 1)
        XCTAssertEqual(dataSource.indexOfFormula(named: "curl"), 2)
    }

    func testIndexOfFormulaNamedReturnsMinusOneWhenAbsent() {
        let manager = BPHomebrewManager.sharedManager()
        manager.installedFormulae = [BPFormula.formula(withName: "wget")]

        let dataSource = BPFormulaeDataSource(mode: BPListMode.installed.rawValue)
        dataSource.refreshBackingArray()

        XCTAssertEqual(dataSource.indexOfFormula(named: "git"), -1)
        XCTAssertEqual(dataSource.indexOfFormula(named: ""), -1)
        XCTAssertEqual(dataSource.indexOfFormula(named: nil), -1)
    }

    func testIndexOfFormulaNamedCaskDistinguishesSameNamedFormulaAndCask() {
        let formula = BPFormula.formula(withName: "tap/tools/shared")
        let cask = BPFormula.formula(withName: "tap/tools/shared")
        cask.cask = true

        let manager = BPHomebrewManager.sharedManager()
        manager.searchFormulae = [formula, cask]

        let dataSource = BPFormulaeDataSource(mode: BPListMode.search.rawValue)
        dataSource.refreshBackingArray()

        XCTAssertEqual(dataSource.indexOfFormula(named: "tap/tools/shared", cask: false), 0)
        XCTAssertEqual(dataSource.indexOfFormula(named: "tap/tools/shared", cask: true), 1)
        XCTAssertEqual(dataSource.indexOfFormula(named: "missing", cask: true), -1)
        XCTAssertEqual(dataSource.indexOfFormula(named: "", cask: true), -1)
    }

    // MARK: - sorting (clickable column headers)

    private func sorted(_ formulae: [BPFormula], by key: String, ascending: Bool) -> [BPFormula] {
        let descriptor = NSSortDescriptor(key: key, ascending: ascending)
        return (BPFormulaeDataSource.formulae(formulae, sortedBy: [descriptor]) as? [BPFormula]) ?? []
    }

    private func names(of formulae: [BPFormula]) -> [String] {
        formulae.compactMap(\.name)
    }

    func testSortingByNameIsCaseInsensitiveAndOrdered() {
        let formulae = [
            BPFormula.formula(withName: "Wget"),
            BPFormula.formula(withName: "ack"),
            BPFormula.formula(withName: "git")
        ]

        XCTAssertEqual(
            names(of: sorted(formulae, by: Self.kColumnIdentifierName, ascending: true)),
            ["ack", "git", "Wget"],
            "a case-sensitive sort would put Wget first, which reads as broken"
        )
    }

    func testSortingByNameDescendingReversesIt() {
        let formulae = [
            BPFormula.formula(withName: "ack"),
            BPFormula.formula(withName: "git")
        ]

        XCTAssertEqual(
            names(of: sorted(formulae, by: Self.kColumnIdentifierName, ascending: false)),
            ["git", "ack"]
        )
    }

    func testSortingByVersionOrdersNumericallyNotLexically() {
        // Lexically "10.0" sorts before "9.0"; version columns must not do that.
        let formulae = [
            BPFormula.formula(withName: "a", andVersion: "9.0"),
            BPFormula.formula(withName: "b", andVersion: "10.0"),
            BPFormula.formula(withName: "c", andVersion: "2.0")
        ]

        XCTAssertEqual(
            names(of: sorted(formulae, by: Self.kColumnIdentifierVersion, ascending: true)),
            ["c", "a", "b"]
        )
    }

    func testSortingByStatusUsesEnumOrderNotTheLocalizedString() {
        let manager = BPHomebrewManager.sharedManager()
        let outdated = BPFormula.formula(withName: "outdated", version: "1.0", andLatestVersion: "2.0")
        let installed = BPFormula.formula(withName: "installed", andVersion: "1.0")
        let absent = BPFormula.formula(withName: "absent")
        manager.installedFormulae = [installed, outdated]
        manager.outdatedFormulae = [outdated]

        let result = sorted([outdated, absent, installed], by: Self.kColumnIdentifierStatus, ascending: true)

        XCTAssertEqual(names(of: result), ["absent", "installed", "outdated"])
    }

    func testSortingIsStableForEqualKeys() {
        let formulae = [
            BPFormula.formula(withName: "first", andVersion: "1.0"),
            BPFormula.formula(withName: "second", andVersion: "1.0"),
            BPFormula.formula(withName: "third", andVersion: "1.0")
        ]

        XCTAssertEqual(
            names(of: sorted(formulae, by: Self.kColumnIdentifierVersion, ascending: true)),
            ["first", "second", "third"]
        )
    }

    func testNoDescriptorsLeavesTheOrderAlone() {
        let formulae = [
            BPFormula.formula(withName: "b"),
            BPFormula.formula(withName: "a")
        ]
        let result = (BPFormulaeDataSource.formulae(formulae, sortedBy: []) as? [BPFormula]) ?? []
        XCTAssertEqual(names(of: result), ["b", "a"])
    }

    func testAMissingVersionSortsBeforeAPresentOne() {
        let formulae = [
            BPFormula.formula(withName: "has", andVersion: "1.0"),
            BPFormula.formula(withName: "none")
        ]

        XCTAssertEqual(
            names(of: sorted(formulae, by: Self.kColumnIdentifierVersion, ascending: true)),
            ["none", "has"]
        )
    }
}
