import XCTest
import Foundation

/// Feeds one canned string, so BPFormula parses real `brew info` output.
private final class BPLiteralInfoProvider: NSObject, BPFormulaDataProvider {
    var info: String?

    func information(forFormulaName name: String?) -> String? {
        info
    }
}

final class BPBrewCompatibilityTests: XCTestCase, @unchecked Sendable {

    override func setUpWithError() throws {
        try super.setUpWithError()

        if ProcessInfo.processInfo.environment["CAKEBREW_BREW_COMPAT"] != "1" {
            throw XCTSkip("set CAKEBREW_BREW_COMPAT=1 to run the parsers against real brew")
        }
    }

    /// Runs brew through a login shell, the way BPHomebrewInterface does.
    private func brew(_ arguments: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-l", "-c", "brew \"$@\"", "brew"] + arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        task.standardInput = FileHandle.nullDevice

        nonisolated(unsafe) let collected = NSMutableData()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { h in
            collected.append(h.availableData)
        }

        do {
            try task.run()
        } catch {
            XCTFail("could not run brew: \(error.localizedDescription)")
            return ""
        }

        task.waitUntilExit()
        handle.readabilityHandler = nil
        collected.append(handle.readDataToEndOfFile())

        return String(data: collected as Data, encoding: .utf8) ?? ""
    }

    // MARK: - brew info

    func testBrewInfoForAnInstalledFormulaStillParses() {
        // wget is installed by the workflow before this runs.
        let provider = BPLiteralInfoProvider()
        provider.info = brew(["info", "wget"])
        XCTAssertGreaterThan(provider.info?.count ?? 0, 0, "brew info produced nothing")

        let formula = BPCompatFormula.formula(withName: "wget")
        formula.provider = provider
        XCTAssertTrue(formula.getInformation(), "brew info output no longer parses")

        XCTAssertGreaterThan(formula.latestVersion?.count ?? 0, 0, "version went missing")
        XCTAssertFalse(formula.latestVersion?.contains("==>") ?? true, "section marker leaked into the version")
        XCTAssertNotNil(formula.website, "homepage went missing")
        XCTAssertGreaterThan(formula.shortDescription?.count ?? 0, 0, "description went missing")

        // The exact drift this suite exists to catch.
        XCTAssertFalse(
            formula.installPath?.hasPrefix("Installed (") ?? true,
            "installPath is the marker line again: \(String(describing: formula.installPath))"
        )
        XCTAssertFalse(
            formula.installPath?.hasPrefix("Aliases:") ?? true,
            "installPath picked up the aliases line: \(String(describing: formula.installPath))"
        )
        XCTAssertFalse(formula.installPath?.hasPrefix("From:") ?? true, "installPath: \(String(describing: formula.installPath))")
        XCTAssertFalse(formula.installPath?.hasPrefix("License:") ?? true, "installPath: \(String(describing: formula.installPath))")
        XCTAssertGreaterThan(formula.installPath?.count ?? 0, 0, "an installed formula reported no build")
    }

    func testBrewInfoForAFormulaThatIsNotInstalledStillParses() {
        let provider = BPLiteralInfoProvider()
        provider.info = brew(["info", "cowsay"])

        let formula = BPCompatFormula.formula(withName: "cowsay")
        formula.provider = provider
        XCTAssertTrue(formula.getInformation())

        XCTAssertGreaterThan(formula.latestVersion?.count ?? 0, 0)
        XCTAssertNil(formula.installPath, "a formula that isn't installed reported a location")
    }

    // MARK: - list parsers

    func testInstalledListStillParses() {
        let output = brew(["list", "--versions"])
        XCTAssertGreaterThan(output.count, 0, "brew list produced nothing")

        let formulae = BPHomebrewInterfaceListCallInstalled().parseData(output)
        XCTAssertGreaterThan(formulae.count, 0, "installed list parsed to nothing")
        XCTAssertGreaterThan(formulae.first?.name?.count ?? 0, 0, "parsed a formula with no name")
        XCTAssertGreaterThan(formulae.first?.version?.count ?? 0, 0, "parsed a formula with no version")
    }

    func testOutdatedListStillParses() {
        // May legitimately be empty; parsing must not blow up either way.
        let output = brew(["outdated", "--formula", "--verbose"])
        let formulae = BPHomebrewInterfaceListCallUpgradeable().parseData(output)

        for formula in formulae {
            XCTAssertGreaterThan(formula.name?.count ?? 0, 0, "outdated entry with no name")
            XCTAssertGreaterThan(formula.latestVersion?.count ?? 0, 0, "outdated entry with no target version")
        }
    }

    func testInstalledCasksListStillParses() {
        let output = brew(["list", "--cask", "--versions"])
        let casks = BPHomebrewInterfaceListCallInstalledCasks().parseData(output)

        for cask in casks {
            XCTAssertGreaterThan(cask.name?.count ?? 0, 0, "installed cask with no name")
            XCTAssertTrue(cask.cask, "a cask parsed by the cask list must be flagged as one")
        }
    }

    func testAllCasksCatalogStillParses() {
        let output = brew(["casks"])
        XCTAssertGreaterThan(output.count, 0, "brew casks produced nothing")

        let casks = BPHomebrewInterfaceListCallAllCasks().parseData(output)
        XCTAssertGreaterThan(casks.count, 100, "the cask catalog parsed to almost nothing")
        XCTAssertTrue(casks.first?.cask ?? false)
    }

    // MARK: - services

    func testServicesJSONStillParses() {
        let json = brew(["services", "list", "--json"])
        XCTAssertGreaterThan(json.count, 0, "brew services produced nothing")

        // An empty list is fine; malformed JSON or a renamed key is not.
        let services = BPService.services(fromJSONString: json)
        XCTAssertNotNil(services, "brew services list --json no longer parses")

        for service in services {
            XCTAssertGreaterThan(service.name?.count ?? 0, 0, "service with no name")
        }
    }
}
