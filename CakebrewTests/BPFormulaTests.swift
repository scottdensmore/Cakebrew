import XCTest
import AppKit
import Foundation

@objc(BPFormulaTestDataProvider)
final class BPFormulaTestDataProvider: NSObject, BPFormulaDataProvider {
    func information(forFormulaName name: String?) -> String? {
        guard let name else { return nil }
        switch name {
        case "ffmpeg":
            return fileContent(forFileName: "brewInfo_ffmpeg")
        case "mysql":
            return fileContent(forFileName: "brewInfo_mysql")
        case "percona-server":
            return fileContent(forFileName: "brewInfo_percona-server")
        case "bfg":
            return fileContent(forFileName: "brewInfo_bfg")
        case "acme":
            return fileContent(forFileName: "brewInfo_acme")
        case "fakeformula":
            return fileContent(forFileName: "brewInfo_fakeformula")
        case "bison":
            return fileContent(forFileName: "brewInfo_bison")
        case "sbtenv":
            return fileContent(forFileName: "brewInfo_sbtenv")
        case "nmap":
            return fileContent(forFileName: "brewInfo_nmap")
        default:
            return nil
        }
    }

    private func fileContent(forFileName fileName: String) -> String? {
        guard let path = Bundle(for: Self.self).path(forResource: fileName, ofType: "txt") else {
            return nil
        }
        return try? String(contentsOfFile: path, encoding: .utf8)
    }
}

final class BPFormulaTests: XCTestCase, @unchecked Sendable {
    private static let ffmpegFormula: BPCustomFormula = {
        let f = BPCustomFormula.formula(withName: "ffmpeg")
        f.needsInformation = true
        return f
    }()

    private static let mysqlFormula: BPCustomFormula = {
        let f = BPCustomFormula.formula(withName: "mysql")
        f.needsInformation = true
        return f
    }()

    private static let perconaFormula: BPCustomFormula = {
        let f = BPCustomFormula.formula(withName: "percona-server")
        f.needsInformation = true
        return f
    }()

    private static let acmeFormula: BPCustomFormula = {
        let f = BPCustomFormula.formula(withName: "acme")
        f.needsInformation = true
        return f
    }()

    private static let bfgFormula: BPCustomFormula = {
        let f = BPCustomFormula.formula(withName: "bfg")
        f.needsInformation = true
        return f
    }()

    private static let bisonFormula: BPCustomFormula = {
        let f = BPCustomFormula.formula(withName: "bison")
        f.needsInformation = true
        return f
    }()

    private static let sbtenvFormula: BPCustomFormula = {
        let f = BPCustomFormula.formula(withName: "sbtenv")
        f.needsInformation = true
        return f
    }()

    private static let nmapFormula: BPCustomFormula = {
        let f = BPCustomFormula.formula(withName: "nmap")
        f.needsInformation = true
        return f
    }()

    private var formula: BPFormula?

    func testFormulaCreation() {
        formula = BPFormula.formula(withName: "abcde", version: "1", andLatestVersion: "2")
        XCTAssertNotNil(formula, "Formula failed to initialize")
        XCTAssertEqual(formula?.name, "abcde", "Formula has invalid name")
        XCTAssertEqual(formula?.version, "1", "Formula has invalid name")
        XCTAssertEqual(formula?.latestVersion, "2", "Formula has invalid name")
    }

    func testFormulaFullCopy() throws {
        formula = BPCustomFormula.formula(withName: "fakeformula", version: "1", andLatestVersion: "2")
        formula?.needsInformation = true
        let orig = try XCTUnwrap(formula)
        let copiedFormula = try XCTUnwrap(orig.copy() as? BPFormula)

        XCTAssertTrue(orig.name == copiedFormula.name && !(copiedFormula.name ?? "").isEmpty, "Name failed to copy")
        XCTAssertTrue(orig.version == copiedFormula.version && !(copiedFormula.version ?? "").isEmpty, "Version failed to copy")
        XCTAssertTrue(orig.latestVersion == copiedFormula.latestVersion && !(copiedFormula.latestVersion ?? "").isEmpty, "LatestVersion failed to copy")
        XCTAssertTrue(orig.website?.path == copiedFormula.website?.path && !(copiedFormula.website?.path ?? "").isEmpty, "Website failed to copy")
        XCTAssertTrue(orig.shortDescription == copiedFormula.shortDescription && !(copiedFormula.shortDescription ?? "").isEmpty, "ShortDescription failed to copy")
        XCTAssertTrue(orig.dependencies == copiedFormula.dependencies && !(copiedFormula.dependencies ?? "").isEmpty, "Dependencies failed to copy")
        XCTAssertTrue(orig.conflicts == copiedFormula.conflicts && !(copiedFormula.conflicts ?? "").isEmpty, "Conflicts failed to copy")
        XCTAssertTrue(orig.installPath == copiedFormula.installPath && !(copiedFormula.installPath ?? "").isEmpty, "Instal path failed to copy")
        XCTAssertTrue(orig.information == copiedFormula.information && !(copiedFormula.information ?? "").isEmpty, "Console information failed to copy")
        XCTAssertEqual(copiedFormula.options?.count, 27, "Number of formula options does not match")
    }

    func testFormulaConsoleInformation() {
        let provider = BPFormulaTestDataProvider()
        let ffmpegOutput = provider.information(forFormulaName: "ffmpeg")
        XCTAssertEqual(Self.ffmpegFormula.information, ffmpegOutput)
        let mysqlOutput = provider.information(forFormulaName: "mysql")
        XCTAssertEqual(Self.mysqlFormula.information, mysqlOutput)
        let acmeOutput = provider.information(forFormulaName: "acme")
        XCTAssertEqual(Self.acmeFormula.information, acmeOutput)
        let bfgOutput = provider.information(forFormulaName: "bfg")
        XCTAssertEqual(Self.bfgFormula.information, bfgOutput)
        let perconaOutput = provider.information(forFormulaName: "percona-server")
        XCTAssertEqual(Self.perconaFormula.information, perconaOutput)
        let bisonOutput = provider.information(forFormulaName: "bison")
        XCTAssertEqual(Self.bisonFormula.information, bisonOutput)
        let sbtenvOutput = provider.information(forFormulaName: "sbtenv")
        XCTAssertEqual(Self.sbtenvFormula.information, sbtenvOutput)
        let nmapOutput = provider.information(forFormulaName: "nmap")
        XCTAssertEqual(Self.nmapFormula.information, nmapOutput)
    }

    func testFormulaWebsite() {
        XCTAssertEqual(Self.ffmpegFormula.website?.absoluteString, "https://ffmpeg.org/")
        XCTAssertEqual(Self.mysqlFormula.website?.absoluteString, "https://dev.mysql.com/doc/refman/5.6/en/")
        XCTAssertEqual(Self.acmeFormula.website?.absoluteString, "https://web.archive.org/web/20150520143433/https://www.esw-heim.tu-clausthal.de/~marco/smorbrod/acme/")
        XCTAssertEqual(Self.bfgFormula.website?.absoluteString, "https://rtyley.github.io/bfg-repo-cleaner/")
        XCTAssertEqual(Self.perconaFormula.website?.absoluteString, "https://www.percona.com")
        XCTAssertEqual(Self.bisonFormula.website?.absoluteString, "https://www.gnu.org/software/bison/")
        XCTAssertEqual(Self.sbtenvFormula.website?.absoluteString, "https://github.com/mazgi/sbtenv")
    }

    func testFormulaConflicts() {
        XCTAssertEqual(Self.mysqlFormula.conflicts, "mariadb, mysql-cluster, mysql-connector-c, percona-server")
        XCTAssertEqual(Self.perconaFormula.conflicts, "mariadb, mysql, mysql-cluster, mysql-connector-c, mysql-connector-c")
    }

    func testFormulaNilConflicts() {
        XCTAssertNil(Self.ffmpegFormula.conflicts)
        XCTAssertNil(Self.acmeFormula.conflicts)
        XCTAssertNil(Self.bfgFormula.conflicts)
        XCTAssertNil(Self.bisonFormula.conflicts)
        XCTAssertNil(Self.sbtenvFormula.conflicts)
    }

    func testFormulaDependencies() {
        XCTAssertEqual(
            Self.ffmpegFormula.dependencies,
            "Build: pkg-config ✔, texi2html ✘, yasm ✘; Recommended: x264 ✘, lame ✘, libvo-aacenc ✘, xvid ✘; Optional: faac ✘, fontconfig ✘, freetype ✘, theora ✘, libvorbis ✘, libvpx ✘, rtmpdump ✘, opencore-amr ✘, libass ✘, openjpeg ✘, speex ✘, schroedinger ✘, fdk-aac ✘, opus ✘, frei0r ✘, libcaca ✘, libbluray ✘, libsoxr ✘, libquvi ✘, libvidstab ✘, x265 ✘, openssl ✘, libssh ✘, webp ✘, zeromq ✘"
        )
        XCTAssertEqual(Self.mysqlFormula.dependencies, "Build: cmake ✘; Required: openssl ✘")
        XCTAssertEqual(Self.perconaFormula.dependencies, "Build: cmake ✘; Required: openssl ✘")
    }

    func testFormulaNilDependencies() {
        XCTAssertNil(Self.acmeFormula.dependencies)
        XCTAssertNil(Self.bfgFormula.dependencies)
        XCTAssertNil(Self.bisonFormula.dependencies)
        XCTAssertNil(Self.sbtenvFormula.dependencies)
    }

    func testFormulaShortDescription() {
        XCTAssertEqual(Self.ffmpegFormula.shortDescription, "Play, record, convert, and stream audio and video")
        XCTAssertEqual(Self.mysqlFormula.shortDescription, "Open source relational database management system")
        XCTAssertEqual(Self.acmeFormula.shortDescription, "Crossassembler for multiple environments")
        XCTAssertEqual(Self.bfgFormula.shortDescription, "Removes large files or passwords from Git history like git-filter-branch does, but faster.")
        XCTAssertEqual(Self.perconaFormula.shortDescription, "Drop-in MySQL replacement")
        XCTAssertEqual(Self.bisonFormula.shortDescription, "Parser generator")
    }

    func testFormulaWithoutShortDescription() {
        XCTAssertNil(Self.sbtenvFormula.shortDescription)
    }

    func testFormulaInstallPath() {
        XCTAssertEqual(Self.mysqlFormula.installPath, "/usr/local/Cellar/mysql/5.6.21 (9621 files, 339M) *")
    }

    func testFormulaNilInstallPath() {
        XCTAssertNil(Self.ffmpegFormula.installPath)
        XCTAssertNil(Self.acmeFormula.installPath, "")
        XCTAssertNil(Self.bfgFormula.installPath)
        XCTAssertNil(Self.perconaFormula.installPath)
        XCTAssertNil(Self.sbtenvFormula.installPath)
    }

    func testFormulaInstallPathKegOnly() {
        XCTAssertEqual(Self.bisonFormula.installPath, "This formula is keg-only.")
    }

    func testFormulaLatestVersion() {
        XCTAssertEqual(Self.ffmpegFormula.latestVersion, "stable 2.7.2, HEAD")
        XCTAssertEqual(Self.mysqlFormula.latestVersion, "stable 5.6.26")
        XCTAssertEqual(Self.acmeFormula.latestVersion, "stable 0.91, devel 0.93")
        XCTAssertEqual(Self.bfgFormula.latestVersion, "stable 1.12.4")
        XCTAssertEqual(Self.perconaFormula.latestVersion, "stable 5.6.25-73.1")
        XCTAssertEqual(Self.bisonFormula.latestVersion, "stable 3.0.4")
        XCTAssertEqual(Self.sbtenvFormula.latestVersion, "stable 0.0.8, HEAD")
    }

    func testFormulaNumberOfOptions() {
        XCTAssertEqual(Self.ffmpegFormula.options?.count ?? 0, 33)
        XCTAssertEqual(Self.mysqlFormula.options?.count ?? 0, 8)
        XCTAssertEqual(Self.acmeFormula.options?.count ?? 0, 0)
        XCTAssertEqual(Self.bfgFormula.options?.count ?? 0, 0)
        XCTAssertEqual(Self.perconaFormula.options?.count ?? 0, 5)
        XCTAssertEqual(Self.bisonFormula.options?.count ?? 0, 0)
    }

    func testFormulaOptions() {
        // testing boundaries only
        if let options = Self.perconaFormula.options as? [BPFormulaOption], options.count >= 5 {
            XCTAssertEqual(options[0].name, "--universal")
            XCTAssertEqual(options[0].explanation, "Build a universal binary")
            XCTAssertEqual(options[4].name, "--with-tests")
            XCTAssertEqual(options[4].explanation, "Build with unit tests")
        }
        if let options = Self.ffmpegFormula.options as? [BPFormulaOption], options.count >= 33 {
            XCTAssertEqual(options[0].name, "--with-faac")
            XCTAssertEqual(options[0].explanation, "Build with faac support")
            XCTAssertEqual(options[32].name, "--HEAD")
            XCTAssertEqual(options[32].explanation, "Install HEAD version")
        }
        if let options = Self.mysqlFormula.options as? [BPFormulaOption], options.count >= 8 {
            XCTAssertEqual(options[0].name, "--universal")
            XCTAssertEqual(options[0].explanation, "Build a universal binary")
            XCTAssertEqual(options[7].name, "--with-tests")
            XCTAssertEqual(options[7].explanation, "Build with unit tests")
        }
    }

    func testFormulaObserverAddition() throws {
        let observerFormula = BPCustomFormula.formula(withName: "acme")
        XCTAssertTrue(observerFormula.observerAdded)
        let formulaCopy = try XCTUnwrap(observerFormula.copy() as? BPCustomFormula)
        XCTAssertTrue(formulaCopy.observerAdded)
    }

    func testFormulaNotificationUpdate() {
        let customFormula = BPCustomFormula.formula(withName: "acme")
        let exp = expectation(forNotification: BPFormula.didUpdateNotification, object: customFormula, handler: nil)

        customFormula.needsInformation = true
        wait(for: [exp], timeout: 0.5)
    }

    // MARK: - shortLatestVersion

    func testShortLatestVersionExtractsFromFourComponentString() {
        // "stable 1.6.23 (bottled), HEAD" -> "1.6.23"
        let f = BPFormula.formula(withName: "foo", version: "1.0", andLatestVersion: "stable 1.6.23 (bottled), HEAD")
        XCTAssertEqual(f.shortLatestVersion, "1.6.23")
    }

    func testShortLatestVersionExtractsFromThreeComponentString() {
        // "stable 1.6.23 (bottled)" -> "1.6.23"
        let f = BPFormula.formula(withName: "foo", version: "1.0", andLatestVersion: "stable 1.6.23 (bottled)")
        XCTAssertEqual(f.shortLatestVersion, "1.6.23")
    }

    func testShortLatestVersionReturnsPlainVersionUnchanged() {
        let f = BPFormula.formula(withName: "foo", version: "1.0", andLatestVersion: "1.6.23")
        XCTAssertEqual(f.shortLatestVersion, "1.6.23")
    }

    func testShortLatestVersionReturnsTwoComponentStringUnchanged() {
        // Boundary: only 3- or 4-component strings are treated as the verbose form.
        let f = BPFormula.formula(withName: "foo", version: "1.0", andLatestVersion: "stable 1.6.23")
        XCTAssertEqual(f.shortLatestVersion, "stable 1.6.23")
    }

    func testShortLatestVersionIsNilWhenLatestVersionMissing() {
        let f = BPFormula.formula(withName: "foo")
        XCTAssertNil(f.shortLatestVersion)
    }

    // MARK: - getInformation robustness

    func testGetInformationDoesNotCrashOnMalformedOutput() {
        // `brew info` can return output that doesn't match the expected layout
        // (errors, taps, new formats). getInformation must never crash on it.
        let malformedInputs = [
            "no colon on the first line\na description\nhttps://example.com\n",
            "foo: stable 1.0\n",
            "\n\n",
            "==> Caveats\nsomething unexpected\n",
            "foo:\n",
            "foo: stable 1.0\nConflicts\n"
        ]

        for input in malformedInputs {
            let malformed = BPFormula.formula(withName: "malformed")
            malformed.setValue(input, forKey: "information")
            XCTAssertNoThrow(
                _ = malformed.getInformation(),
                "getInformation must not crash on malformed input: \(input)"
            )
        }
    }

    func testGetInformationStillParsesWellFormedOutput() {
        // Guarding malformed input must not regress the normal happy path.
        let f = BPFormula.formula(withName: "goodformula")
        f.setValue(
            "goodformula: stable 2.5.0\nA well-formed formula.\nhttps://example.com\nNot installed\n",
            forKey: "information"
        )

        XCTAssertNoThrow(_ = f.getInformation())
        XCTAssertEqual(f.latestVersion, "stable 2.5.0")
        XCTAssertEqual(f.shortDescription, "A well-formed formula.")
        XCTAssertEqual(f.website?.absoluteString, "https://example.com")
    }

    // MARK: - cask info parsing (`brew info --cask` output shape)

    func testGetInformationParsesInstalledCaskOutput() {
        let cask = BPFormula.formula(withName: "bbedit")
        cask.cask = true
        cask.setValue(
            "==> bbedit (BBEdit): 16.0.1 (auto_updates)\n"
                + "Text, code, and markup editor\n"
                + "https://www.barebones.com/products/bbedit/\n"
                + "Installed (on request)\n"
                + "/usr/local/Caskroom/bbedit/16.0.1 (69.8MB)\n"
                + "From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/b/bbedit.rb\n",
            forKey: "information"
        )

        XCTAssertNoThrow(_ = cask.getInformation())
        XCTAssertEqual(cask.latestVersion, "16.0.1", "the (auto_updates) marker is stripped")
        XCTAssertEqual(cask.shortDescription, "Text, code, and markup editor")
        XCTAssertEqual(cask.website?.absoluteString, "https://www.barebones.com/products/bbedit/")
        XCTAssertEqual(cask.installPath, "/usr/local/Caskroom/bbedit/16.0.1 (69.8MB)")
    }

    func testGetInformationParsesNotInstalledCaskOutput() {
        let cask = BPFormula.formula(withName: "firefox")
        cask.cask = true
        cask.setValue(
            "==> firefox (Mozilla Firefox): 152.0.5 (auto_updates)\n"
                + "Web browser\n"
                + "https://www.mozilla.org/firefox/\n"
                + "Not installed\n"
                + "From: https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/f/firefox.rb\n",
            forKey: "information"
        )

        XCTAssertNoThrow(_ = cask.getInformation())
        XCTAssertEqual(cask.latestVersion, "152.0.5")
        XCTAssertEqual(cask.shortDescription, "Web browser")
        XCTAssertNil(cask.installPath, "a not-installed cask has no install path")
    }

    func testGetInformationParsesCaskWithoutAutoUpdates() {
        let cask = BPFormula.formula(withName: "someapp")
        cask.cask = true
        cask.setValue(
            "==> someapp: 2.0\n"
                + "Some application\n"
                + "https://example.com/\n"
                + "Not installed\n",
            forKey: "information"
        )

        XCTAssertNoThrow(_ = cask.getInformation())
        XCTAssertEqual(cask.latestVersion, "2.0")
        XCTAssertEqual(cask.shortDescription, "Some application")
    }

    // MARK: - cask flag

    func testCaskFlagDefaultsToNo() {
        XCTAssertFalse(BPFormula.formula(withName: "wget").cask)
    }

    func testCopyPreservesCaskFlag() throws {
        let cask = BPFormula.formula(withName: "google-chrome", andVersion: "120.0")
        cask.cask = true

        let copy = try XCTUnwrap(cask.copy() as? BPFormula)
        XCTAssertTrue(copy.cask, "copying must preserve the cask flag")
    }

    func testSecureCodingRoundTripPreservesCaskFlag() throws {
        let cask = BPFormula.formula(withName: "google-chrome", andVersion: "120.0")
        cask.cask = true

        let data = try NSKeyedArchiver.archivedData(withRootObject: cask, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClass: BPFormula.self, from: data))
        XCTAssertTrue(decoded.cask, "secure-coding round trip must preserve the cask flag")
    }

    // MARK: - namesFromListOutput: (parses `brew uses` dependents output)

    func testNamesFromListOutputSplitsNewlineSeparatedNames() {
        let names = BPFormula.names(fromListOutput: "cmake\nffmpeg\nsdl2\n")
        XCTAssertEqual(names, ["cmake", "ffmpeg", "sdl2"])
    }

    func testNamesFromListOutputSplitsSpaceSeparatedNames() {
        // `brew uses` can print names on one whitespace-separated line.
        let names = BPFormula.names(fromListOutput: "cmake ffmpeg sdl2")
        XCTAssertEqual(names, ["cmake", "ffmpeg", "sdl2"])
    }

    func testNamesFromListOutputIgnoresBlankAndWhitespaceEntries() {
        let names = BPFormula.names(fromListOutput: "cmake\n\n   \nffmpeg\n")
        XCTAssertEqual(names, ["cmake", "ffmpeg"])
    }

    func testNamesFromListOutputEmptyReturnsEmptyArray() {
        XCTAssertEqual(BPFormula.names(fromListOutput: ""), [])
        XCTAssertEqual(BPFormula.names(fromListOutput: "\n  \n"), [])
    }

    // MARK: - coding round trip

    /// A formula with every field distinct, so a mismatched coding key shows up as
    /// one field carrying another's value rather than as a plausible-looking blank.
    private func fullyPopulatedFormula() -> BPFormula {
        let f = BPFormula.formula(withName: "mysql", version: "5.6.21", andLatestVersion: "8.0.0")
        f.setValue("/usr/local/Cellar/mysql/5.6.21", forKey: "installPath")
        f.setValue(URL(string: "https://example.com/mysql"), forKey: "website")
        f.setValue("openssl, zlib", forKey: "dependencies")
        f.setValue("mariadb, percona-server", forKey: "conflicts")
        f.setValue("Open source relational database", forKey: "shortDescription")
        f.setValue("the full brew info text", forKey: "information")
        f.cask = true
        return f
    }

    private func assertFormula(_ copy: BPFormula, matchesOriginal original: BPFormula) {
        XCTAssertEqual(copy.name, original.name)
        XCTAssertEqual(copy.version, original.version)
        XCTAssertEqual(copy.latestVersion, original.latestVersion)
        XCTAssertEqual(copy.installPath, original.installPath)
        XCTAssertEqual(copy.website, original.website)
        XCTAssertEqual(copy.dependencies, original.dependencies)
        XCTAssertEqual(copy.conflicts, original.conflicts)
        XCTAssertEqual(copy.information, original.information)
        XCTAssertEqual(copy.cask, original.cask)

        // The one that was wrong: shortDescription was decoded from the conflicts
        // key, so a cached formula came back describing itself as its own
        // conflicts list.
        XCTAssertEqual(
            copy.shortDescription,
            original.shortDescription,
            "shortDescription must not come back as another field"
        )
        XCTAssertNotEqual(
            copy.shortDescription,
            original.conflicts,
            "shortDescription decoded from the conflicts key"
        )
    }

    func testASecureCodingRoundTripPreservesEveryField() throws {
        let original = fullyPopulatedFormula()

        // The same class set BPHomebrewManager uses to read the catalog cache.
        let classes: [AnyClass] = [
            NSDictionary.self,
            NSArray.self,
            NSMutableArray.self,
            BPFormula.self,
            NSString.self,
            NSURL.self,
            NSNumber.self,
            BPFormulaOption.self
        ]

        let data = try NSKeyedArchiver.archivedData(withRootObject: original, requiringSecureCoding: true)
        let decoded = try XCTUnwrap(NSKeyedUnarchiver.unarchivedObject(ofClasses: classes, from: data) as? BPFormula)

        assertFormula(decoded, matchesOriginal: original)
    }

    func testCopyingPreservesEveryField() throws {
        let original = fullyPopulatedFormula()
        let copy = try XCTUnwrap(original.copy() as? BPFormula)
        assertFormula(copy, matchesOriginal: original)
    }
}
