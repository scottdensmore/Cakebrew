import XCTest
import AppKit
import Foundation

@objc(BPModernInfoDataProvider)
final class BPModernInfoDataProvider: NSObject, BPFormulaDataProvider {
    private static let fixtures: [String: String] = [
        "wget": "brewInfo_modern_installed",
        "tree": "brewInfo_modern_notinstalled",
        "openssl@3": "brewInfo_modern_aliases",
        "libffi": "brewInfo_modern_kegonly"
    ]

    func information(forFormulaName name: String?) -> String? {
        guard let name,
              let fixture = Self.fixtures[name],
              let path = Bundle(for: Self.self).path(forResource: fixture, ofType: "txt") else {
            return nil
        }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}

final class BPFormulaModernInfoTests: XCTestCase, @unchecked Sendable {

    private func parsedFormula(named name: String) -> BPFormula {
        let formula = BPModernFormula.formula(withName: name)
        XCTAssertTrue(formula.getInformation(), "parsing \(name) should succeed")
        return formula
    }

    func testDependenciesStopAtAnyFollowingSection() {
        for section in ["Analytics", "Requirements", "Installed Versions", "New Homebrew Section", "Caveats", "Options"] {
            let formula = BPFormula.formula(withName: "automake")
            formula.information = """
            ==> automake: stable 1.19
            Makefile generator
            https://example.com
            Not installed
            ==> Dependencies
            Required (1): autoconf
            Recursive Runtime (2): all installed ✔
            ==> \(section)
            install: 38,099 (30 days)
            """
            XCTAssertTrue(formula.getInformation())
            XCTAssertEqual(formula.dependencies, "Required (1): autoconf; Recursive Runtime (2): all installed ✔", section)
        }
    }

    func testDependencyLinksContainOnlyUniquePackageNames() {
        let snapshot = BPSelectedFormulaSnapshot(name: "automake", cask: false, isInstalled: true,
            isPinned: false, installPath: nil, latestVersion: nil,
            dependencies: "Build: pkg-config ✔; Required (2): autoconf ✔, openssl@3 ✘; Recommended: autoconf ✔; Recursive Runtime (2): all installed ✔",
            conflicts: nil, shortDescription: nil)
        XCTAssertEqual(snapshot.dependencyNames, ["pkg-config", "autoconf", "openssl@3"])
    }

    func testInspectorMetadataUsesTheSameInformationResponse() {
        let formula = parsedFormula(named: "wget")
        let details = BPFormulaInspectorDetails(information: formula.information)
        XCTAssertEqual(details.license, "GPL-3.0-or-later")
        XCTAssertEqual(details.source?.absoluteString, "https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/w/wget.rb")
        XCTAssertEqual(details.information, formula.information)
        XCTAssertNil(BPFormulaInspectorDetails(information: "From: file:///tmp/untrusted.rb").source)
        XCTAssertNil(BPFormulaInspectorDetails(information: nil).license)
    }

    // MARK: - installed formula

    func testInstalledFormulaFieldsAreParsed() {
        let wget = parsedFormula(named: "wget")

        XCTAssertEqual(
            wget.latestVersion,
            "stable 1.25.0 (bottled), HEAD",
            "the \"==> \" header prefix must not leak into the version"
        )
        XCTAssertEqual(wget.shortDescription, "Internet file retriever")
        XCTAssertEqual(wget.website?.absoluteString, "https://www.gnu.org/software/wget/")
    }

    func testInstalledFormulaReportsTheInstalledVersionLineNotTheInstalledMarker() {
        // The actual regression: installPath used to be the literal string
        // "Installed (on request)".
        let wget = parsedFormula(named: "wget")

        XCTAssertNotEqual(
            wget.installPath,
            "Installed (on request)",
            "the \"Installed\" marker line is not an install location"
        )
        XCTAssertEqual(
            wget.installPath,
            "wget 1.25.0 (92 files, 4.7MB) [Linked]",
            "modern brew reports the installed build here, not a Cellar path"
        )
    }

    // MARK: - formula that is not installed

    func testNotInstalledFormulaHasNoInstallPath() {
        let tree = parsedFormula(named: "tree")

        XCTAssertNil(tree.installPath, "a formula that isn't installed has nothing to report")
        XCTAssertEqual(tree.latestVersion, "stable 2.3.2 (bottled)")
        XCTAssertEqual(tree.shortDescription, "Display directories as trees (with optional color/HTML output)")
        XCTAssertEqual(tree.website?.absoluteString, "https://oldmanprogrammer.net/source.php?dir=projects/tree")
    }

    // MARK: - the Aliases line

    func testAliasesLineDoesNotDisplaceTheOtherFields() {
        // "Aliases:" sits between the homepage and the installed marker, so a
        // positional walk reads it as the install location.
        let openssl = parsedFormula(named: "openssl@3")

        XCTAssertEqual(openssl.shortDescription, "Cryptography and SSL/TLS Toolkit")
        XCTAssertEqual(openssl.website?.absoluteString, "https://openssl-library.org")
        XCTAssertEqual(openssl.installPath, "openssl@3 3.6.3 (7,633 files, 38.1MB) [Linked]")
        XCTAssertFalse(openssl.installPath?.hasPrefix("Aliases") ?? true, "the aliases line is not an install location")
    }

    // MARK: - keg-only

    func testKegOnlyFormulaParses() {
        // The header carries a trailing "[keg-only]" marker and the formula has a
        // Caveats section after Options.
        let libffi = parsedFormula(named: "libffi")

        XCTAssertEqual(libffi.latestVersion, "stable 3.8.0 (bottled), HEAD [keg-only]")
        XCTAssertEqual(libffi.shortDescription, "Portable Foreign Function Interface library")
        XCTAssertEqual(
            libffi.installPath,
            "libffi 3.8.0 (18 files, 881.2KB)",
            "keg-only builds are unlinked, so there is no [Linked] suffix"
        )
    }

    // MARK: - fields never carry section markers

    func testNoParsedFieldRetainsASectionHeaderMarker() {
        for name in ["wget", "tree", "openssl@3", "libffi"] {
            let formula = parsedFormula(named: name)

            XCTAssertFalse(formula.latestVersion?.contains("==>") ?? false, "\(name) version")
            XCTAssertFalse(formula.installPath?.contains("==>") ?? false, "\(name) install path")
            XCTAssertFalse(formula.shortDescription?.contains("==>") ?? false, "\(name) description")
            XCTAssertFalse(formula.installPath?.hasPrefix("From:") ?? false, "\(name) install path")
            XCTAssertFalse(formula.installPath?.hasPrefix("License:") ?? false, "\(name) install path")
        }
    }
}
