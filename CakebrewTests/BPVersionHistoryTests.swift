import Foundation
import XCTest

private final class BPVersionTransportProbe: BPHomebrewInterface, @unchecked Sendable {
    var receivedProgress: Progress?
    var commandCount = 0
    var synchronous = false
    var completionMessage = true

    override func performAsyncBrewCommand(withArguments arguments: [Any]?, wrapsSynchronousRequest: Bool,
                                         progress: Progress?, includesCompletionMessage: Bool,
                                         dataReturnBlock block: (@Sendable (String) -> Void)?) -> Bool {
        commandCount += 1
        receivedProgress = progress
        synchronous = wrapsSynchronousRequest
        completionMessage = includesCompletionMessage
        block?("shell greeting\n+++++Cakebrew+++++\n{\"formulae\":[]}")
        return true
    }
}

private final class BPVersionCommandRecorder: @unchecked Sendable {
    var commands: [[String]] = []
    var taps = "homebrew/core\ncakebrew/versions\n"
    var existingRecipe = true
    var stable = "1.2.3"
    var linked = true
    var pinned = false
    var installedVersion: String?
    var targetLinkedVersion = ""
    var wrongLink = false
    var ignorePin = false
    var wrongRestore = false
    var originalLinkedVersion = "9.0"
    var fail: String?
    var onRun: (([String]) -> Void)?

    func read(_ arguments: [String]) -> (succeeded: Bool, output: String) {
        if arguments == ["tap"] { return (true, taps) }
        let target = arguments.last?.hasPrefix("cakebrew/versions") == true
        if target && !existingRecipe { return (false, "No available formula") }
        let data = try! JSONSerialization.data(withJSONObject: ["formulae": [[
            "versions": ["stable": target ? stable : "9.0"],
            "installed": [["version": installedVersion ?? stable]], "pinned": pinned,
            "linked_keg": target ? targetLinkedVersion : (linked ? originalLinkedVersion : "")
        ]]])
        return (true, String(decoding: data, as: UTF8.self))
    }

    func run(_ arguments: [String]) -> Bool {
        commands.append(arguments)
        onRun?(arguments)
        if arguments.first == "extract" { existingRecipe = true }
        if let fail, arguments.first == fail { return false }
        if arguments.first == "pin", !ignorePin { pinned = true }
        if arguments.first == "link", arguments.last?.hasPrefix("cakebrew/versions") == true {
            targetLinkedVersion = wrongLink ? "9.9.9" : stable
        }
        if arguments.first == "unlink", arguments.last?.hasPrefix("cakebrew/versions") == true { targetLinkedVersion = "" }
        if arguments == ["link", "--force", "homebrew/core/wget"], wrongRestore { originalLinkedVersion = "8.0" }
        return true
    }
}

final class BPVersionHistoryTests: XCTestCase, @unchecked Sendable {
    private var release: BPVersionRelease {
        BPVersionRelease(version: "1.2.3", commit: String(repeating: "a", count: 40), date: "2025-01-01T00:00:00Z",
                         message: "wget 1.2.3", source: BPVersionHistorySource(url: URL(string:
                            "https://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/w/wget.rb")!)!)
    }

    func testMetadataReadIsCancellableAndStripsShellStartupOutput() {
        let interface = BPVersionTransportProbe()
        let progress = Progress(totalUnitCount: 1)
        let result = interface.readVersionHistoryCommand(["info", "--json=v2", "wget"], progress: progress)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.output, "{\"formulae\":[]}")
        XCTAssertTrue(interface.receivedProgress === progress)
        XCTAssertTrue(interface.synchronous)
        XCTAssertFalse(interface.completionMessage)
    }

    func testCancelledMetadataReadDoesNotStartACommand() {
        let interface = BPVersionTransportProbe()
        let progress = Progress(totalUnitCount: 1)
        progress.cancel()
        XCTAssertFalse(interface.readVersionHistoryCommand(["tap"], progress: progress).succeeded)
        XCTAssertEqual(interface.commandCount, 0)
    }

    func testSourcePreservesRepositoryPathAndLegacyHistory() throws {
        let source = release.source
        XCTAssertEqual(source.formula, "homebrew/core/wget")
        XCTAssertEqual(source.paths, ["Formula/w/wget.rb", "Formula/wget.rb"])
        XCTAssertEqual(source.url(commit: release.commit, raw: true).absoluteString,
                       "https://raw.githubusercontent.com/Homebrew/homebrew-core/\(release.commit)/Formula/w/wget.rb")
        let custom = try XCTUnwrap(BPVersionHistorySource(url: URL(string: "https://github.com/example/homebrew-tools/blob/main/Formula/tool.rb")!))
        XCTAssertEqual(custom.tap, "example/tools")
        XCTAssertEqual(custom.paths, ["Formula/tool.rb"])
    }

    func testRejectsUntrustedAndInvalidSources() {
        for string in ["file:///tmp/tool.rb", "http://github.com/Homebrew/homebrew-core/blob/HEAD/Formula/a.rb",
                       "https://example.com/Homebrew/homebrew-core/blob/HEAD/Formula/a.rb",
                       "https://github.com/Homebrew/homebrew-core/raw/HEAD/Formula/a.rb",
                       "https://github.com/Homebrew/brew/blob/HEAD/Formula/a.rb"] {
            XCTAssertNil(BPVersionHistorySource(url: URL(string: string)!), string)
        }
    }

    func testRecognizesReleasesWithoutInventingVersionsFromMaintenanceCommits() {
        for title in ["wget 1.2.3", "wget: 1.2.3", "wget v1.2.3", "wget: update to 1.2.3", "wget 1.2.3 (#123)"] {
            XCTAssertEqual(BPVersionRelease.version(in: title, name: "wget"), "1.2.3", title)
        }
        for title in ["wget: update 1.2.3 bottle.", "wget: revision bump", "wget: update resource", "other 1.2.3", "wget: disable 1.2.3"] {
            XCTAssertNil(BPVersionRelease.version(in: title, name: "wget"), title)
        }
        XCTAssertEqual(BPVersionRelease.version(in: "openssl@3 3.5.2", name: "openssl@3"), "3.5.2")
    }

    func testHistoricalDetailsReadSourceWithoutEvaluatingRubyOrResourceVersion() {
        let text = """
        class Wget < Formula
          desc "Download files"
          homepage "https://example.com"
          license "GPL-3.0-or-later"
          version "1.2.3"
          depends_on "openssl@3"
          resource "dependency" do
            version "999"
          end
          system "this must never execute"
        end
        """
        let details = BPHistoricalFormulaDetails(source: text)
        XCTAssertEqual(details.explicitVersion, "1.2.3")
        XCTAssertEqual(details.description, "Download files")
        XCTAssertEqual(details.dependencies, ["\"openssl@3\""])
        XCTAssertEqual(details.source, text)
    }

    func testInstallUsesDedicatedTapAndPinsAfterSuccessfulInstallWithoutChangingLinks() {
        let recorder = BPVersionCommandRecorder()
        let result = BPVersionInstaller.install(release, makeActive: false, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(recorder.commands, [["install", "--formula", "--skip-link", release.target], ["pin", release.target]])
    }

    func testNewHistoryRecipeExtractsSelectedCommitAndVersionWithoutOverwriting() {
        let recorder = BPVersionCommandRecorder()
        recorder.taps = ""
        recorder.existingRecipe = false
        let result = BPVersionInstaller.install(release, makeActive: false, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(recorder.commands.prefix(3), [["tap-new", "--no-git", "cakebrew/versions"], ["tap", "--force", "homebrew/core"],
            ["extract", "--version=1.2.3", "--git-revision=\(release.commit)", "homebrew/core/wget", "cakebrew/versions"]])
        XCTAssertFalse(recorder.commands.flatMap { $0 }.contains("--overwrite"))
    }

    func testThirdPartyHistoryUsesAnIndependentTapToAvoidFormulaNameCollisions() {
        let source = BPVersionHistorySource(url: URL(string: "https://github.com/example/homebrew-tools/blob/main/Formula/wget.rb")!)!
        let custom = BPVersionRelease(version: release.version, commit: release.commit, date: "", message: "", source: source)
        XCTAssertNotEqual(custom.destinationTap, release.destinationTap)
        XCTAssertNotEqual(custom.target, release.target)
        let recorder = BPVersionCommandRecorder()
        recorder.taps = ""
        recorder.existingRecipe = false
        let result = BPVersionInstaller.install(custom, makeActive: false, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(recorder.commands.prefix(3), [["tap-new", "--no-git", custom.destinationTap], ["tap", "--force", "example/tools"],
            ["extract", "--version=1.2.3", "--git-revision=\(release.commit)", "example/tools/wget", custom.destinationTap]])
        XCTAssertEqual(recorder.commands.last, ["pin", custom.target])
    }

    func testMismatchedRecipeNeverInstallsOrPins() {
        let recorder = BPVersionCommandRecorder()
        recorder.stable = "4.5.6"
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testInstallFailureNeverPinsOrUnlinksCurrentVersion() {
        let recorder = BPVersionCommandRecorder()
        recorder.fail = "install"
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.commands.map { $0[0] }, ["install"])
    }

    func testAlreadyInstalledDifferentKegIsNotPinnedAsTheRequestedRelease() {
        let recorder = BPVersionCommandRecorder()
        recorder.installedVersion = "9.9.9"
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.commands.map { $0[0] }, ["install"])
    }

    func testSuccessfulPinCommandMustStillBeConfirmedByHomebrew() {
        let recorder = BPVersionCommandRecorder()
        recorder.ignorePin = true
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.commands.map { $0[0] }, ["install", "pin"])
    }

    func testWrongActiveVersionIsUnlinkedAndPreviousVersionRestored() {
        let recorder = BPVersionCommandRecorder()
        recorder.wrongLink = true
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.commands.suffix(2), [["unlink", release.target], ["link", "--force", "homebrew/core/wget"]])
    }

    func testPinFailureNeverChangesCurrentLinks() {
        let recorder = BPVersionCommandRecorder()
        recorder.fail = "pin"
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.commands.map { $0[0] }, ["install", "pin"])
    }

    func testActivationOnlyUnlinksAfterInstallAndPinSucceed() {
        let recorder = BPVersionCommandRecorder()
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(recorder.commands, [["install", "--formula", "--skip-link", release.target], ["pin", release.target],
                                          ["unlink", "homebrew/core/wget"], ["link", "--force", release.target]])
    }

    func testFailedActivationRestoresCurrentLinks() {
        let recorder = BPVersionCommandRecorder()
        recorder.onRun = { arguments in
            if arguments == ["link", "--force", self.release.target] { recorder.fail = "link" }
            if arguments == ["link", "--force", "homebrew/core/wget"] { recorder.fail = nil }
        }
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.commands.suffix(3), [["link", "--force", release.target], ["unlink", release.target],
                                                  ["link", "--force", "homebrew/core/wget"]])
        XCTAssertTrue(result.message.contains("restored"))
    }

    func testFailedActivationWithoutOriginalLinksCleansUpPartialTargetLinks() {
        let recorder = BPVersionCommandRecorder()
        recorder.linked = false
        recorder.fail = "link"
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.commands.suffix(2), [["link", "--force", release.target], ["unlink", release.target]])
        XCTAssertFalse(recorder.commands.contains(["unlink", "homebrew/core/wget"]))
    }

    func testCancellationAfterUnlinkStillRunsRestoration() {
        let recorder = BPVersionCommandRecorder()
        let progress = Progress()
        recorder.onRun = { if $0.first == "unlink" { progress.cancel() } }
        let result = BPVersionInstaller.install(release, makeActive: true, progress: progress, read: recorder.read,
                                               run: recorder.run, restore: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.commands.last, ["link", "--force", "homebrew/core/wget"])
        XCTAssertFalse(recorder.commands.contains(["link", "--force", release.target]))
    }

    func testRestorationMustConfirmTheExactPreviouslyActiveVersion() {
        let recorder = BPVersionCommandRecorder()
        recorder.wrongLink = true
        recorder.wrongRestore = true
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("restoring the previous links failed"))
    }

    func testReportsRestorationFailureAndDoesNotClaimSuccess() {
        let recorder = BPVersionCommandRecorder()
        recorder.fail = "link"
        let result = BPVersionInstaller.install(release, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("restoring the previous links failed"))
    }

    func testRejectsCasksAndNonNumericVersionsBeforeAnyCommands() {
        let recorder = BPVersionCommandRecorder()
        let source = BPVersionHistorySource(url: URL(string: "https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/f/firefox.rb")!)!
        let cask = BPVersionRelease(version: "1.2.3", commit: release.commit, date: "", message: "", source: source)
        let prerelease = BPVersionRelease(version: "1.2.3-beta1", commit: release.commit, date: "", message: "", source: release.source)
        for version in [cask, prerelease] {
            XCTAssertFalse(BPVersionInstaller.install(version, makeActive: true, progress: Progress(), read: recorder.read, run: recorder.run).succeeded)
        }
        XCTAssertTrue(recorder.commands.isEmpty)
    }
}

private final class BPVersionHistoryURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: Sendable { let status: Int; let data: Data }
    private static let lock = NSLock()
    nonisolated(unsafe) private static var routes: [String: [String: Response]] = [:]

    static func session(responses: [String: Response]) -> URLSession {
        let id = UUID().uuidString
        lock.lock()
        routes[id] = responses
        lock.unlock()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BPVersionHistoryURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Cakebrew-Test": id]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let key = url.path.hasSuffix("/commits")
            ? "\(query.first { $0.name == "path" }?.value ?? "")|\(query.first { $0.name == "page" }?.value ?? "")"
            : url.path
        Self.lock.lock()
        let response = Self.routes[request.value(forHTTPHeaderField: "X-Cakebrew-Test") ?? ""]?[key]
            ?? Response(status: 404, data: Data())
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: response.status,
                                                            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension BPVersionHistoryTests {
    private func commits(_ messages: [String]) throws -> Data {
        try JSONSerialization.data(withJSONObject: messages.enumerated().map { index, message in
            ["sha": String(format: "%040d", index + 1), "commit": ["message": message,
                "committer": ["date": "2025-01-01T00:00:00Z"]]] as [String: Any]
        })
    }

    func testHistoryDeduplicatesReleasesAndContinuesBeforeTheFormulaPathMove() async throws {
        let session = BPVersionHistoryURLProtocol.session(responses: [
            "Formula/w/wget.rb|1": .init(status: 200, data: try commits(["wget 1.2.3", "wget 1.2.3", "wget: update 1.2.3 bottle."])),
            "Formula/wget.rb|1": .init(status: 200, data: try commits(["wget 1.1.0"]))
        ])
        let client = BPVersionHistoryClient(session: session)
        let page = try await client.history(source: release.source)
        XCTAssertEqual(page.releases.map(\.version), ["1.2.3"])
        XCTAssertTrue(page.hasMore)
        XCTAssertEqual(page.nextPath, 1)
        let older = try await client.history(source: release.source, pathIndex: page.nextPath, page: page.nextPage)
        XCTAssertEqual(older.releases.map(\.version), ["1.1.0"])
        XCTAssertEqual(older.releases.first?.source.path, "Formula/wget.rb")
        XCTAssertFalse(older.hasMore)
    }

    func testHistoryRateLimitIsAnActionableError() async throws {
        let session = BPVersionHistoryURLProtocol.session(responses: ["Formula/w/wget.rb|1": .init(status: 403, data: Data())])
        do {
            _ = try await BPVersionHistoryClient(session: session).history(source: release.source)
            XCTFail("Rate limited responses must not be treated as empty history")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("limit"), error.localizedDescription)
        }
    }

    func testMissingHistoricalSourceDoesNotBecomeVersionInformation() async throws {
        let session = BPVersionHistoryURLProtocol.session(responses: [:])
        do {
            _ = try await BPVersionHistoryClient(session: session).information(for: release)
            XCTFail("Missing source must not be displayed as formula metadata")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("404"), error.localizedDescription)
        }
    }
}

private final class BPCaskVersionRecorder: @unchecked Sendable {
    var commands: [[String]] = []
    var written = false
    var pinned = true
    var installed: String? = "9.0"
    var recipeVersion = "1.2.3,456"
    var checksum = String(repeating: "a", count: 64)
    var fail: String?
    var wrongInstalledVersion = false
    var ignorePin = false
    var supportsPin = true
    var pinnedVersionOverride: String?
    var onRun: (([String]) -> Void)?

    func read(_ arguments: [String]) -> (succeeded: Bool, output: String) {
        if arguments == ["tap"] { return (true, "homebrew/cask") }
        if arguments.first == "--repository" { return (true, "/tmp/local-history-tap") }
        var metadata: [String: Any] = ["version": recipeVersion, "installed": installed as Any? ?? NSNull(), "sha256": checksum]
        if supportsPin {
            metadata["pinned"] = pinned
            metadata["pinned_version"] = pinned ? ((pinnedVersionOverride ?? installed) as Any? ?? NSNull()) : NSNull()
        }
        let data = try! JSONSerialization.data(withJSONObject: ["casks": [metadata]])
        return (true, String(decoding: data, as: UTF8.self))
    }

    func run(_ arguments: [String]) -> Bool {
        commands.append(arguments)
        onRun?(arguments)
        if arguments.first == fail { return false }
        if ["install", "reinstall"].contains(arguments.first ?? "") {
            installed = wrongInstalledVersion ? "99.0" : recipeVersion
        }
        if arguments.first == "unpin" { pinned = false }
        if arguments.first == "pin", !ignorePin { pinned = true }
        return true
    }

    func write(_ repository: String, _ release: BPVersionRelease, _ source: String) throws { written = true }
}

extension BPVersionHistoryTests {
    private var caskRelease: BPVersionRelease {
        BPVersionRelease(version: "1.2.3,456", commit: String(repeating: "a", count: 40), date: "", message: "firefox 1.2.3,456",
                         source: BPVersionHistorySource(url: URL(string: "https://github.com/Homebrew/homebrew-cask/blob/HEAD/Casks/f/firefox.rb")!)!)
    }
    private var caskSource: String {
        "# Historical source\ncask \"firefox\" do\n  version \"1.2.3,456\"\n  sha256 \"\(String(repeating: "a", count: 64))\"\nend\n"
    }
    private func installCask(_ recorder: BPCaskVersionRecorder, progress: Progress = Progress(), text: String? = nil) -> BPVersionInstallResult {
        BPVersionCaskInstaller.install(caskRelease, sourceText: text ?? caskSource, progress: progress,
                                      read: recorder.read, run: recorder.run, restore: recorder.run, write: recorder.write)
    }

    func testCaskHistoryPreservesCompoundVersionAndLegacyPath() {
        XCTAssertEqual(BPVersionRelease.version(in: "firefox 1.2.3,456 (#123)", name: "firefox"), "1.2.3,456")
        XCTAssertTrue(caskRelease.canInstall)
        XCTAssertEqual(caskRelease.source.paths, ["Casks/f/firefox.rb", "Casks/firefox.rb"])
        XCTAssertTrue(caskRelease.target.hasSuffix("/firefox"), "Preserve the token so app artifacts aren't installed twice")
        let other = BPVersionRelease(version: "1.2.3,456", commit: String(repeating: "b", count: 40), date: "", message: "", source: caskRelease.source)
        XCTAssertNotEqual(caskRelease.destinationTap, other.destinationTap, "Historical cask definitions remain immutable")
    }

    func testCaskReplacementFetchesBeforeUnpinningAndPinsExactInstalledVersion() {
        let recorder = BPCaskVersionRecorder()
        XCTAssertTrue(installCask(recorder).succeeded)
        XCTAssertTrue(recorder.written)
        let commands = recorder.commands
        let fetch = commands.firstIndex { $0.first == "fetch" }!
        let unpin = commands.firstIndex { $0.first == "unpin" }!
        let reinstall = commands.firstIndex { $0.first == "reinstall" }!
        let pin = commands.firstIndex { $0.first == "pin" }!
        XCTAssertLessThan(fetch, unpin)
        XCTAssertLessThan(unpin, reinstall)
        XCTAssertLessThan(reinstall, pin)
        XCTAssertEqual(commands[reinstall], ["reinstall", "--cask", "--require-sha", caskRelease.target])
        XCTAssertEqual(commands[pin], ["pin", "--cask", caskRelease.target])
        XCTAssertFalse(commands.joined().contains("--force"))
        XCTAssertFalse(commands.joined().contains("--zap"))
    }

    func testHistoricalCaskCanBeInstalledWithoutAnExistingApp() {
        let recorder = BPCaskVersionRecorder()
        recorder.installed = nil
        recorder.pinned = false
        XCTAssertTrue(installCask(recorder).succeeded)
        XCTAssertTrue(recorder.commands.contains(["install", "--cask", "--require-sha", caskRelease.target]))
        XCTAssertFalse(recorder.commands.contains { $0.first == "unpin" })
    }

    func testCaskWithoutVerifiedChecksumOrMatchingVersionNeverReplacesApp() {
        for invalid in ["no_check", "", "123"] {
            let recorder = BPCaskVersionRecorder()
            recorder.checksum = invalid
            XCTAssertFalse(installCask(recorder).succeeded)
            XCTAssertFalse(recorder.commands.contains { ["fetch", "unpin", "install", "reinstall"].contains($0.first ?? "") })
        }
        let recorder = BPCaskVersionRecorder()
        recorder.recipeVersion = "99.0"
        XCTAssertFalse(installCask(recorder).succeeded)
        XCTAssertFalse(recorder.commands.contains { $0.first == "reinstall" })
    }

    func testCaskMissingDownloadKeepsAppAndExistingPin() {
        let recorder = BPCaskVersionRecorder()
        recorder.fail = "fetch"
        XCTAssertFalse(installCask(recorder).succeeded)
        XCTAssertEqual(recorder.installed, "9.0")
        XCTAssertTrue(recorder.pinned)
        XCTAssertFalse(recorder.commands.contains { $0.first == "unpin" })
    }

    func testFailedCaskReplacementRestoresExistingPin() {
        let recorder = BPCaskVersionRecorder()
        recorder.fail = "reinstall"
        let result = installCask(recorder)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(recorder.pinned)
        XCTAssertEqual(recorder.commands.last, ["pin", "--cask", caskRelease.source.formula])
        XCTAssertTrue(result.message.contains("may need to be reinstalled"))
    }

    func testCancelledCaskReplacementRestoresPinWithRecoveryRunner() {
        let recorder = BPCaskVersionRecorder()
        let progress = Progress()
        recorder.onRun = { if $0.first == "unpin" { progress.cancel() } }
        XCTAssertFalse(installCask(recorder, progress: progress).succeeded)
        XCTAssertTrue(recorder.pinned)
        XCTAssertFalse(recorder.commands.contains { $0.first == "reinstall" })
    }

    func testCaskInstallDoesNotReportSuccessForWrongVersionOrUnconfirmedPin() {
        let recorder = BPCaskVersionRecorder()
        recorder.wrongInstalledVersion = true
        XCTAssertFalse(installCask(recorder).succeeded)
        let unpinnable = BPCaskVersionRecorder()
        unpinnable.ignorePin = true
        XCTAssertFalse(installCask(unpinnable).succeeded)
    }

    func testCaskPinMustReferToTheSelectedInstalledVersion() {
        let recorder = BPCaskVersionRecorder()
        recorder.pinnedVersionOverride = "9.0"
        let result = installCask(recorder)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("pin could not be confirmed"))
    }

    func testCaskRecoveryDoesNotClaimSuccessForAnUnconfirmedPin() {
        let recorder = BPCaskVersionRecorder()
        recorder.fail = "reinstall"
        recorder.ignorePin = true
        let result = installCask(recorder)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.message.contains("Restoring the previous pin failed"))
    }

    func testCaskRecipeWriteFailureStopsBeforeDownloadOrReplacement() {
        let recorder = BPCaskVersionRecorder()
        let result = BPVersionCaskInstaller.install(caskRelease, sourceText: caskSource, progress: Progress(),
            read: recorder.read, run: recorder.run, restore: recorder.run,
            write: { _, _, _ in throw BPVersionHistoryError.message("Read-only tap") })
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.message, "Read-only tap")
        XCTAssertFalse(recorder.commands.contains { ["fetch", "unpin", "reinstall", "install"].contains($0.first ?? "") })
    }

    func testOldHomebrewWithoutCaskPinSupportIsRejectedBeforeAppChanges() {
        let recorder = BPCaskVersionRecorder()
        recorder.supportsPin = false
        XCTAssertFalse(installCask(recorder).succeeded)
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testCaskTokenOrSourceVersionMismatchNeverRunsHomebrew() {
        let recorder = BPCaskVersionRecorder()
        XCTAssertFalse(installCask(recorder, text: caskSource.replacingOccurrences(of: "firefox", with: "other")).succeeded)
        XCTAssertFalse(installCask(recorder, text: caskSource.replacingOccurrences(of: "1.2.3,456", with: "99.0")).succeeded)
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testCaskDefinitionIsSavedVerbatimAndNeverOverwritesDifferentSource() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let root = base.appendingPathComponent("homebrew-\(caskRelease.destinationTap.split(separator: "/").last!)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try BPVersionCaskInstaller.saveDefinition(repository: root.path, release: caskRelease, text: caskSource)
        try BPVersionCaskInstaller.saveDefinition(repository: root.path, release: caskRelease, text: caskSource)
        XCTAssertThrowsError(try BPVersionCaskInstaller.saveDefinition(repository: root.path, release: caskRelease, text: "different"))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("Casks/firefox.rb"), encoding: .utf8), caskSource)
    }
}

private final class BPLatestVersionRecorder: @unchecked Sendable {
    var commands: [[String]] = []
    var cask = false
    var oldPinned = true
    var latestPinned = true
    var oldLinked = "1.2.3"
    var latestLinked = ""
    var latestInstalled = "1.0"
    var stable = "2.0"
    var revision = 0
    var fail: String?
    var wrongInstall = false
    var ignoreUnpin = false
    var wrongLink = false
    var onRun: (([String]) -> Void)?
    var expected: String { revision == 0 ? stable : "\(stable)_\(revision)" }

    func read(_ args: [String]) -> (succeeded: Bool, output: String) {
        let historical = args.last?.hasPrefix("cakebrew/") == true
        let info: [String: Any]
        if cask {
            info = ["version": historical ? "1.2.3" : stable,
                    "installed": latestInstalled, "pinned": oldPinned,
                    "pinned_version": oldPinned ? latestInstalled as Any : NSNull()]
        } else {
            info = ["versions": ["stable": historical ? "1.2.3" : stable],
                    "revision": historical ? 0 : revision,
                    "installed": [["version": historical ? "1.2.3" : latestInstalled]],
                    "linked_keg": historical ? oldLinked : latestLinked,
                    "pinned": historical ? oldPinned : latestPinned]
        }
        let data = try! JSONSerialization.data(withJSONObject: [cask ? "casks" : "formulae": [info]])
        return (true, String(decoding: data, as: UTF8.self))
    }
    func run(_ args: [String]) -> Bool {
        commands.append(args)
        onRun?(args)
        if args.first == fail { return false }
        let historical = args.last?.hasPrefix("cakebrew/") == true
        if args.first == "unpin", !ignoreUnpin {
            if historical || cask { oldPinned = false } else { latestPinned = false }
        }
        if args.first == "pin" {
            if historical || cask { oldPinned = true } else { latestPinned = true }
        }
        if ["install", "reinstall"].contains(args.first ?? ""), !wrongInstall { latestInstalled = expected }
        if args.first == "unlink" {
            if historical { oldLinked = "" } else { latestLinked = "" }
        }
        if args.first == "link" {
            if historical { oldLinked = "1.2.3" }
            else { latestLinked = wrongLink ? "99.0" : expected }
        }
        return true
    }
}

extension BPVersionHistoryTests {
    private func returnLatest(_ recorder: BPLatestVersionRecorder, progress: Progress = Progress()) -> BPVersionInstallResult {
        let chosen = recorder.cask
            ? BPVersionRelease(version: "1.2.3", commit: release.commit, date: "", message: "", source: caskRelease.source)
            : release
        return BPVersionLatestInstaller.install(chosen, progress: progress,
            read: recorder.read, run: recorder.run, recover: recorder.run, recoverRead: recorder.read)
    }
    func testReturnActionAvailabilityChecksInstalledVersionWithoutRunningMutations() {
        let recorder = BPLatestVersionRecorder()
        XCTAssertTrue(BPVersionLatestInstaller.isInstalled(release, read: recorder.read))
        recorder.cask = true
        let cask = BPVersionRelease(version: "1.2.3", commit: release.commit, date: "", message: "", source: caskRelease.source)
        XCTAssertFalse(BPVersionLatestInstaller.isInstalled(cask, read: recorder.read))
        recorder.latestInstalled = "1.2.3"
        XCTAssertTrue(BPVersionLatestInstaller.isInstalled(cask, read: recorder.read))
        XCTAssertTrue(recorder.commands.isEmpty)
    }

    func testReturnToLatestFormulaVerifiesInstallBeforeChangingLinksAndUnpinsBothPackages() {
        let recorder = BPLatestVersionRecorder()
        let result = returnLatest(recorder)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertFalse(recorder.oldPinned)
        XCTAssertFalse(recorder.latestPinned)
        XCTAssertEqual(recorder.latestLinked, "2.0")
        let install = recorder.commands.firstIndex { $0.first == "install" }!
        let unlink = recorder.commands.firstIndex { $0.first == "unlink" }!
        let unpinOld = recorder.commands.firstIndex { $0 == ["unpin", "--formula", release.target] }!
        XCTAssertLessThan(install, unlink)
        XCTAssertLessThan(unlink, unpinOld)
        XCTAssertEqual(recorder.commands.first, ["update"])
        XCTAssertTrue(recorder.commands.contains(["install", "--formula", "--skip-link", release.source.formula]))
        XCTAssertFalse(recorder.commands.joined().contains("--overwrite"))
        XCTAssertFalse(recorder.commands.contains { $0.first == "uninstall" })
    }
    func testReturnToLatestFormulaIncludesHomebrewRevisionWhenCheckingInstalledAndActiveVersion() {
        let recorder = BPLatestVersionRecorder()
        recorder.revision = 2
        XCTAssertTrue(returnLatest(recorder).succeeded)
        XCTAssertEqual(recorder.latestLinked, "2.0_2")
    }
    func testFailedLatestDownloadPreservesHistoricalPinsAndLinks() {
        let recorder = BPLatestVersionRecorder()
        recorder.fail = "fetch"
        XCTAssertFalse(returnLatest(recorder).succeeded)
        XCTAssertTrue(recorder.oldPinned)
        XCTAssertTrue(recorder.latestPinned)
        XCTAssertEqual(recorder.oldLinked, "1.2.3")
        XCTAssertFalse(recorder.commands.contains { ["unpin", "unlink"].contains($0.first ?? "") })
    }
    func testFailedLatestInstallAndIncorrectInstalledVersionKeepHistoricalLinks() {
        for wrong in [false, true] {
            let recorder = BPLatestVersionRecorder()
            recorder.wrongInstall = wrong
            recorder.fail = wrong ? nil : "install"
            XCTAssertFalse(returnLatest(recorder).succeeded)
            XCTAssertTrue(recorder.oldPinned)
            XCTAssertTrue(recorder.latestPinned)
            XCTAssertEqual(recorder.oldLinked, "1.2.3")
            XCTAssertFalse(recorder.commands.contains { $0.first == "unlink" })
        }
    }
    func testLatestLinkFailureRestoresHistoricalLinksAndPriorPins() {
        let recorder = BPLatestVersionRecorder()
        recorder.wrongLink = true
        let result = returnLatest(recorder)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(recorder.oldLinked, "1.2.3")
        XCTAssertTrue(recorder.oldPinned)
        XCTAssertTrue(recorder.latestPinned)
        XCTAssertTrue(result.message.contains("preserved or restored"))
        XCTAssertTrue(recorder.commands.contains(["unlink", "--formula", release.source.formula]))
    }
    func testCancellationAfterHistoricalUnlinkRestoresWithRecoveryRunner() {
        let recorder = BPLatestVersionRecorder()
        let progress = Progress()
        recorder.onRun = { if $0.first == "unlink" { progress.cancel() } }
        XCTAssertFalse(returnLatest(recorder, progress: progress).succeeded)
        XCTAssertEqual(recorder.oldLinked, "1.2.3")
        XCTAssertTrue(recorder.oldPinned)
        XCTAssertTrue(recorder.latestPinned)
    }
    func testReturnLatestRejectsAnUnconfirmedUnpin() {
        let recorder = BPLatestVersionRecorder()
        recorder.ignoreUnpin = true
        XCTAssertFalse(returnLatest(recorder).succeeded)
        XCTAssertEqual(recorder.oldLinked, "1.2.3")
        XCTAssertFalse(recorder.commands.contains { $0.first == "install" })
    }
    func testReturnToLatestCaskFetchesBeforeUnpinningThenReinstallsFromUpstream() {
        let recorder = BPLatestVersionRecorder()
        recorder.cask = true
        recorder.latestInstalled = "1.2.3"
        let result = returnLatest(recorder)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertFalse(recorder.oldPinned)
        XCTAssertEqual(recorder.latestInstalled, "2.0")
        let fetch = recorder.commands.firstIndex { $0.first == "fetch" }!
        let unpin = recorder.commands.firstIndex { $0.first == "unpin" }!
        XCTAssertLessThan(fetch, unpin)
        XCTAssertTrue(recorder.commands.contains(["reinstall", "--cask", caskRelease.source.formula]))
        XCTAssertFalse(recorder.commands.joined().contains("--zap"))
    }
    func testReturnToCurrentCaskRecipeSupportsHomebrewLatestVersions() {
        let recorder = BPLatestVersionRecorder()
        recorder.cask = true
        recorder.latestInstalled = "1.2.3"
        recorder.stable = "latest"
        XCTAssertTrue(returnLatest(recorder).succeeded)
        XCTAssertEqual(recorder.latestInstalled, "latest")
        XCTAssertFalse(recorder.oldPinned)
    }

    func testFailedLatestCaskReplacementRestoresAndConfirmsPinPolicy() {
        let recorder = BPLatestVersionRecorder()
        recorder.cask = true
        recorder.latestInstalled = "1.2.3"
        recorder.fail = "reinstall"
        let result = returnLatest(recorder)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(recorder.oldPinned)
        XCTAssertEqual(recorder.latestInstalled, "1.2.3")
        XCTAssertTrue(result.message.contains("may need to be reinstalled"))
    }
    func testLatestCaskRequiresSelectedHistoricalVersionToActuallyBeInstalled() {
        let recorder = BPLatestVersionRecorder()
        recorder.cask = true
        XCTAssertFalse(returnLatest(recorder).succeeded)
        XCTAssertTrue(recorder.commands.isEmpty)
    }
    func testUpstreamReceiptPreservesThirdPartyOriginAndIgnoresOtherPackageKinds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = BPVersionHistorySource(url: URL(string: "https://github.com/example/homebrew-tools/blob/main/Formula/wget.rb")!)!
        let chosen = BPVersionRelease(version: "1.2.3", commit: release.commit, date: "", message: "", source: source)
        try BPVersionReceipt.save(chosen, directory: root)
        XCTAssertEqual(BPVersionReceipt.find(name: "wget@1.2.3", cask: false, directory: root), chosen)
        XCTAssertEqual(BPVersionReceipt.find(name: chosen.target, cask: false, directory: root)?.source.formula, "example/tools/wget")
        XCTAssertNil(BPVersionReceipt.find(name: "wget@1.2.3", cask: true, directory: root))
    }
}

extension BPVersionHistoryTests {
    private func pinnedRead(_ entries: [[String: Any]], cask: Bool = false) throws -> BPVersionInstaller.Read {
        let data = try JSONSerialization.data(withJSONObject: [cask ? "casks" : "formulae": entries])
        let output = String(decoding: data, as: UTF8.self)
        return { _ in (true, output) }
    }
    private func pinnedFormula(_ name: String, tap: String = "homebrew/core") -> [String: Any] {
        ["name": name, "tap": tap, "pinned": true, "installed": [["version": "1.2.3"]], "linked_keg": "1.2.3"]
    }
    func testPinnedResolverSelectsRequestedPackageFromWholeInstalledCatalog() throws {
        let read = try pinnedRead([pinnedFormula("other"), pinnedFormula("wget")])
        let plan = try BPPinnedVersionResolver.resolve(name: "wget", cask: false, read: read, receipt: { _, _ in nil })
        XCTAssertEqual(plan.historical, "homebrew/core/wget")
        XCTAssertEqual(plan.upstream, "homebrew/core/wget")
        XCTAssertFalse(plan.requiresUpstream)
        XCTAssertTrue(plan.isValid)
    }
    func testPinnedResolverUsesInstalledCaskTapAndVersion() throws {
        let read = try pinnedRead([["token": "firefox", "tap": "homebrew/cask", "pinned": true, "installed": "1.2.3"]], cask: true)
        let plan = try BPPinnedVersionResolver.resolve(name: "firefox", cask: true, read: read, receipt: { _, _ in nil })
        XCTAssertEqual(plan.upstream, "homebrew/cask/firefox")
        XCTAssertEqual(plan.version, "1.2.3")
        XCTAssertTrue(plan.cask)
    }
    func testPinnedHistoricalFormulaUsesExactReceiptIncludingThirdPartyTap() throws {
        let source = BPVersionHistorySource(url: URL(string: "https://github.com/example/homebrew-tools/blob/HEAD/Formula/wget.rb")!)!
        let saved = BPVersionRelease(version: "1.2.3", commit: release.commit, date: "", message: "", source: source)
        let tap = saved.destinationTap
        let read = try pinnedRead([pinnedFormula("wget@1.2.3", tap: tap)])
        let plan = try BPPinnedVersionResolver.resolve(name: "wget@1.2.3", cask: false, read: read, receipt: { _, _ in saved })
        XCTAssertEqual(plan.historical, saved.target)
        XCTAssertEqual(plan.upstream, "example/tools/wget")
        XCTAssertFalse(plan.requiresUpstream)
    }
    func testPinnedHistoricalCaskUsesReceiptWithoutSearchingForOriginalPackage() throws {
        let read = try pinnedRead([["token": "firefox", "tap": caskRelease.destinationTap, "pinned": true,
                                  "installed": caskRelease.version]], cask: true)
        let saved = caskRelease
        let plan = try BPPinnedVersionResolver.resolve(name: "firefox", cask: true, read: read, receipt: { _, _ in saved })
        XCTAssertEqual(plan.upstream, "homebrew/cask/firefox")
        XCTAssertEqual(plan.historical, saved.target)
    }
    func testOlderCopiedPackageWithoutReceiptRequiresExplicitUpstream() throws {
        let read = try pinnedRead([pinnedFormula("wget@1.2.3", tap: "cakebrew/versions")])
        var plan = try BPPinnedVersionResolver.resolve(name: "wget@1.2.3", cask: false, read: read, receipt: { _, _ in nil })
        XCTAssertTrue(plan.requiresUpstream)
        XCTAssertFalse(plan.isValid)
        XCTAssertTrue(plan.upstreamCandidates.isEmpty)
        plan.upstream = "homebrew/core/wget"
        XCTAssertTrue(plan.isValid)
    }
    private func originRead(installed: [String: Any], catalog: String,
                            candidates: [[String: Any]], cask: Bool = false,
                            unreadable: String? = nil) throws -> BPVersionInstaller.Read {
        let key = cask ? "casks" : "formulae"
        func json(_ entries: [[String: Any]]) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: [key: entries]), as: UTF8.self)
        }
        let installedJSON = try json([installed])
        var responses: [String: String] = [:]
        for candidate in candidates {
            let name = candidate[cask ? "token" : "name"] as! String
            responses["\(candidate["tap"] as! String)/\(name)"] = try json([candidate])
        }
        let frozen = responses
        return { arguments in
            if arguments.contains("--installed") { return (true, installedJSON) }
            if arguments == [cask ? "casks" : "formulae"] { return (true, catalog) }
            guard let name = arguments.last, name != unreadable, let output = frozen[name] else { return (false, "unavailable") }
            return (true, output)
        }
    }

    func testLegacyCoreFormulaDetectsOriginalWithoutReceipt() throws {
        let read = try originRead(installed: pinnedFormula("wget@1.2.3", tap: "cakebrew/versions"),
                                  catalog: "wget\nhomebrew/core/wget\nexample/tools/wget\ncakebrew/versions/wget@1.2.3",
                                  candidates: [["name": "wget", "tap": "homebrew/core"]])
        let plan = try BPPinnedVersionResolver.resolve(name: "wget@1.2.3", cask: false, read: read, receipt: { _, _ in nil })
        XCTAssertEqual(plan.upstream, "homebrew/core/wget")
        XCTAssertFalse(plan.requiresUpstream)
        XCTAssertTrue(plan.isValid)
    }

    func testLegacyThirdPartyFormulaUsesTapFingerprintInsteadOfCoreNamesake() throws {
        let source = BPVersionHistorySource(url: URL(string: "https://github.com/example/homebrew-tools/blob/HEAD/Formula/wget.rb")!)!
        let saved = BPVersionRelease(version: "1.2.3", commit: release.commit, date: "", message: "", source: source)
        let read = try originRead(installed: pinnedFormula("wget@1.2.3", tap: saved.destinationTap),
                                  catalog: "wget\nexample/tools/wget\nother/tools/wget",
                                  candidates: [["name": "wget", "tap": "example/tools"]])
        let plan = try BPPinnedVersionResolver.resolve(name: "wget@1.2.3", cask: false, read: read, receipt: { _, _ in nil })
        XCTAssertEqual(plan.upstream, "example/tools/wget")
        XCTAssertFalse(plan.requiresUpstream)
    }

    func testLegacyFormulaDoesNotGuessBetweenOriginalVersionedBranches() throws {
        let read = try originRead(installed: pinnedFormula("postgresql@14.1", tap: "cakebrew/versions"),
                                  catalog: "postgresql@15\nhomebrew/core/postgresql@14\npostgresql@14\nexample/tools/postgresql@14\ncakebrew/versions/postgresql@14.1\n--bad", candidates: [])
        let plan = try BPPinnedVersionResolver.resolve(name: "postgresql@14.1", cask: false, read: read, receipt: { _, _ in nil })
        XCTAssertTrue(plan.requiresUpstream)
        XCTAssertTrue(plan.upstream.isEmpty)
        XCTAssertEqual(plan.upstreamCandidates, ["homebrew/core/postgresql@14", "homebrew/core/postgresql@15"])
        XCTAssertFalse(plan.isValid)
        var selected = plan
        selected.upstream = plan.upstreamCandidates[1]
        XCTAssertTrue(selected.isValid)
    }

    func testLegacyCaskDetectsThirdPartyOriginByTokenAndHomepage() throws {
        let installed: [String: Any] = ["token": "firefox", "tap": caskRelease.destinationTap,
            "pinned": true, "installed": "1.2.3", "homepage": "https://EXAMPLE.com/firefox/"]
        let read = try originRead(installed: installed,
            catalog: "firefox\nexample/apps/firefox\ncakebrew/history-123/firefox",
            candidates: [["token": "firefox", "tap": "homebrew/cask", "homepage": "https://mozilla.org/firefox"],
                         ["token": "firefox", "tap": "example/apps", "homepage": "https://example.com/firefox"]], cask: true)
        let plan = try BPPinnedVersionResolver.resolve(name: "firefox", cask: true, read: read, receipt: { _, _ in nil })
        XCTAssertEqual(plan.upstream, "example/apps/firefox")
        XCTAssertFalse(plan.requiresUpstream)
        XCTAssertTrue(plan.isValid)
    }

    func testLegacyCaskDoesNotGuessWhenCompetingTapMatchesOrCannotBeRead() throws {
        let installed: [String: Any] = ["token": "firefox", "tap": caskRelease.destinationTap,
            "pinned": true, "installed": "1.2.3", "homepage": "https://example.com/firefox"]
        let candidates: [[String: Any]] = [
            ["token": "firefox", "tap": "homebrew/cask", "homepage": "https://example.com/firefox"],
            ["token": "firefox", "tap": "example/apps", "homepage": "https://example.com/firefox"]]
        for unavailable in [nil, "example/apps/firefox"] as [String?] {
            let read = try originRead(installed: installed, catalog: "firefox\nexample/apps/firefox",
                                      candidates: candidates, cask: true, unreadable: unavailable)
            let plan = try BPPinnedVersionResolver.resolve(name: "firefox", cask: true, read: read, receipt: { _, _ in nil })
            XCTAssertTrue(plan.requiresUpstream)
            XCTAssertTrue(plan.upstream.isEmpty)
            XCTAssertEqual(plan.upstreamCandidates, ["example/apps/firefox", "homebrew/cask/firefox"])
            XCTAssertFalse(plan.isValid)
            var selected = plan
            selected.upstream = plan.upstreamCandidates[0]
            XCTAssertTrue(selected.isValid)
        }
    }

    func testOriginDetectionRejectsWrongReturnedIdentityAndMissingHomepage() throws {
        let read = try originRead(installed: pinnedFormula("wget@1.2.3", tap: "cakebrew/versions"),
            catalog: "wget", candidates: [["name": "wget", "tap": "other/tools"]])
        let plan = try BPPinnedVersionResolver.resolve(name: "wget@1.2.3", cask: false, read: read, receipt: { _, _ in nil })
        XCTAssertTrue(plan.requiresUpstream)
        let caskRead = try originRead(installed: ["token": "firefox", "tap": caskRelease.destinationTap,
            "pinned": true, "installed": "1.2.3"], catalog: "firefox",
            candidates: [["token": "firefox", "tap": "homebrew/cask"]], cask: true)
        XCTAssertTrue(try BPPinnedVersionResolver.resolve(name: "firefox", cask: true, read: caskRead,
                                                         receipt: { _, _ in nil }).requiresUpstream)
    }

    func testMismatchedReceiptCannotSendAPackageToAnotherUpstream() throws {
        let read = try pinnedRead([pinnedFormula("wget@1.2.3", tap: "cakebrew/versions-unrelated")])
        let saved = release
        let plan = try BPPinnedVersionResolver.resolve(name: "wget@1.2.3", cask: false, read: read, receipt: { _, _ in saved })
        XCTAssertTrue(plan.requiresUpstream)
        XCTAssertTrue(plan.upstream.isEmpty)
    }
    func testAmbiguousOrNoLongerPinnedPackageIsRejectedWithoutChanges() throws {
        let ambiguous = try pinnedRead([pinnedFormula("wget"), pinnedFormula("wget", tap: "example/tools")])
        XCTAssertThrowsError(try BPPinnedVersionResolver.resolve(name: "wget", cask: false, read: ambiguous))
        var unpinned = pinnedFormula("wget")
        unpinned["pinned"] = false
        let read = try pinnedRead([unpinned])
        XCTAssertThrowsError(try BPPinnedVersionResolver.resolve(name: "wget", cask: false, read: read))
    }
    func testPinnedResolverHonorsQualifiedNamesAndFormulaCaskNamespaces() throws {
        let read = try pinnedRead([pinnedFormula("wget"), pinnedFormula("wget", tap: "example/tools")])
        let plan = try BPPinnedVersionResolver.resolve(name: "example/tools/wget", cask: false, read: read, receipt: { _, _ in nil })
        XCTAssertEqual(plan.upstream, "example/tools/wget")
        XCTAssertThrowsError(try BPPinnedVersionResolver.resolve(name: "wget", cask: true, read: read))
    }
    func testReturningAnOrdinaryPinnedFormulaUpgradesInPlaceWithoutUnlinkingLatestKeg() {
        let recorder = BPLatestVersionRecorder()
        let plan = BPVersionReturnPlan(historical: "homebrew/core/wget", upstream: "homebrew/core/wget", cask: false, version: "1.0")
        let result = BPVersionLatestInstaller.install(plan, progress: Progress(), read: recorder.read,
            run: recorder.run, recover: recorder.run, recoverRead: recorder.read)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertFalse(recorder.latestPinned)
        XCTAssertEqual(recorder.latestLinked, "2.0")
        XCTAssertFalse(recorder.commands.contains { $0.first == "unlink" })
        XCTAssertEqual(recorder.commands.filter { $0.first == "unpin" }.count, 1)
    }
    func testOrdinaryPinnedCaskCanReturnToCurrentRecipeInPlace() {
        let recorder = BPLatestVersionRecorder()
        recorder.cask = true
        recorder.latestInstalled = "1.2.3"
        let plan = BPVersionReturnPlan(historical: "homebrew/cask/firefox", upstream: "homebrew/cask/firefox", cask: true, version: "1.2.3")
        let result = BPVersionLatestInstaller.install(plan, progress: Progress(), read: recorder.read,
            run: recorder.run, recover: recorder.run, recoverRead: recorder.read)
        XCTAssertTrue(result.succeeded, result.message)
        XCTAssertFalse(recorder.oldPinned)
        XCTAssertEqual(recorder.latestInstalled, "2.0")
    }

    func testPinnedReviewCannotReplaceAnUnrelatedPackage() {
        XCTAssertFalse(BPVersionReturnPlan(historical: "cakebrew/versions/wget@1.2.3", upstream: "homebrew/core/curl", cask: false, version: "1.2.3").isValid)
        XCTAssertFalse(BPVersionReturnPlan(historical: "cakebrew/history-test/firefox", upstream: "homebrew/cask/chromium", cask: true, version: "1.2.3").isValid)
        XCTAssertTrue(BPVersionReturnPlan(historical: "cakebrew/versions/openssl@3.2.1", upstream: "homebrew/core/openssl@3", cask: false, version: "3.2.1").isValid)
    }

    func testReturnPlanRejectsInvalidOrHistoricalUpstreamBeforeAnyMutation() {
        let recorder = BPLatestVersionRecorder()
        for upstream in ["", "--force", "owner/../wget", "cakebrew/versions/wget@1.2.3", "owner/tap/wget;touch"] {
            let plan = BPVersionReturnPlan(historical: release.target, upstream: upstream, cask: false, version: "1.2.3")
            XCTAssertFalse(BPVersionLatestInstaller.install(plan, progress: Progress(), read: recorder.read,
                run: recorder.run, recover: recorder.run, recoverRead: recorder.read).succeeded)
        }
        XCTAssertTrue(recorder.commands.isEmpty)
    }
}
