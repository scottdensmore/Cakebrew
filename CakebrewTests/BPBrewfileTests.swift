//
//  BPBrewfileTests.swift
//  CakebrewTests
//
//  Deciding what counts as a Brewfile is the part worth testing. Too narrow and
//  the feature does not fire on files people really have; too broad and
//  Cakebrew offers to run `brew bundle` against arbitrary text.
//

import AppKit
import Foundation
import XCTest

private final class BPBrewfileOutputRecorder: @unchecked Sendable {
    var output = ""
}

final class BPBrewfileTests: XCTestCase, @unchecked Sendable {

    func testOnlyConfirmedLocalSaveDestinationCanStartExport() {
        let file = URL(fileURLWithPath: "/fixture/Brewfile")
        XCTAssertEqual(BPBrewfileExportOperation.exportURL(forSaveResponse: NSApplication.ModalResponse.OK.rawValue, url: file), file)
        for response in [NSApplication.ModalResponse.cancel.rawValue, NSApplication.ModalResponse.abort.rawValue, NSApplication.ModalResponse.stop.rawValue] {
            XCTAssertNil(BPBrewfileExportOperation.exportURL(forSaveResponse: response, url: file))
        }
        XCTAssertNil(BPBrewfileExportOperation.exportURL(forSaveResponse: NSApplication.ModalResponse.OK.rawValue, url: nil))
        XCTAssertNil(BPBrewfileExportOperation.exportURL(forSaveResponse: NSApplication.ModalResponse.OK.rawValue, url: URL(string: "https://example.com/Brewfile")))
    }

    func testExportUsesCommandResultForSilentAndUnfamiliarFailures() {
        for output in ["", "permission denied writing destination", "Error: destination unavailable"] {
            let interface = CBExportInterface(uniqueInstance: ())
            interface.commandOutput = output as NSString
            interface.commandSucceeded = false
            let error = interface.runBrewExportTool(withPath: "/fixture/My Brewfile")
            XCTAssertNotNil(error)
            XCTAssertGreaterThan((error?.localizedDescription as NSString?)?.length ?? 0, 0)
            if !output.isEmpty {
                XCTAssertTrue(error?.localizedDescription.contains(output) == true)
            }
            XCTAssertEqual(interface.exportArguments as? [String], ["bundle", "dump", "--force", "--file=/fixture/My Brewfile"])
        }
    }

    func testSuccessfulExportDoesNotInferFailureFromDiagnosticText() {
        let interface = CBExportInterface(uniqueInstance: ())
        interface.commandOutput = "Error: quoted in a successful diagnostic" as NSString
        interface.commandSucceeded = true
        XCTAssertNil(interface.runBrewExportTool(withPath: "/fixture/Brewfile"))
    }

    func testExportRunsOffMainKeepsRunningUntilExitAndCompletesOnceOnMain() {
        for fails in [false, true] {
            let interface = CBDelayedExportInterface(uniqueInstance: ())
            interface.releaseCommand = DispatchSemaphore(value: 0)
            interface.exportError = fails ? NSError(domain: "fixture", code: 7, userInfo: nil) : nil
            let operation = BPBrewfileExportOperation(url: URL(fileURLWithPath: "/fixture/Brewfile"), interface: interface)
            let entered = expectation(description: "command entered")
            let finished = expectation(description: "command finished")
            interface.entered = { entered.fulfill() }
            operation.start(withCompletion: { error in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertFalse(operation.running)
                XCTAssertEqual(error, interface.exportError)
                finished.fulfill()
            })
            wait(for: [entered], timeout: 5)
            XCTAssertTrue(operation.running)
            operation.start(withCompletion: { _ in
                XCTFail("operation must be one shot")
            })
            interface.releaseCommand?.signal()
            wait(for: [finished], timeout: 5)
            XCTAssertEqual(interface.calls, 1)
        }
    }

    func testDirectImportCancellationBetweenRequestAndTaskCreationIsNotLost() {
        let interface = CB151DirectInterface(uniqueInstance: ())
        interface.setValue("/bin/sh", forKey: "path_shell")
        let progress = Progress(totalUnitCount: 1)
        interface.duringFormatting = { progress.cancel() }
        let recorder = BPBrewfileOutputRecorder()
        XCTAssertFalse(
            interface.runBrewImportTool(withPath: "/fixture/Brewfile", progress: progress) { chunk in
                recorder.output.append(chunk)
            }
        )
        XCTAssertEqual(interface.receivedArguments as? [String], ["bundle", "--file=/fixture/Brewfile"])
        XCTAssertFalse(recorder.output.components(separatedBy: "\n").contains("ACTUAL_FIXTURE_LAUNCH"))
        interface.duringFormatting = nil
        recorder.output = ""
        XCTAssertTrue(
            interface.runBrewImportTool(withPath: "/fixture/NextBrewfile", progress: Progress(totalUnitCount: 1)) { chunk in
                recorder.output.append(chunk)
            }
        )
        XCTAssertTrue(recorder.output.components(separatedBy: "\n").contains("ACTUAL_FIXTURE_LAUNCH"))
    }

    func testReviewGroupsDirectEntriesAndReportsInstalledMissingAndUncheckedTotals() {
        let plan = BPBrewfilePlan.plan(
            withString: "brew 'git'\ncask 'firefox'\ntap 'owner/tap'\nmas 'App', id: 123\nvscode 'pub.ext'",
            inventories: ["brew": ["git"], "cask": []]
        )
        XCTAssertTrue(plan.reviewText.contains("Formulae"))
        XCTAssertTrue(plan.reviewText.contains("Casks"))
        XCTAssertTrue(plan.reviewText.contains("Mac App Store"))
        XCTAssertTrue(plan.reviewText.contains("1 installed"))
        XCTAssertTrue(plan.reviewText.contains("1 missing"))
        XCTAssertTrue(plan.reviewText.contains("3 not checked"))
        XCTAssertTrue(plan.reviewText.contains("App (id: 123)"))
    }

    func testHelperTransportIsRejectedWithoutDispatchingAnImport() {
        let interface = CB151ImportInterface(uniqueInstance: ())
        interface.brewTransport = .helper
        let operation = BPBrewfileImportOperation(
            plan: BPBrewfilePlan.plan(withString: "brew 'git'", inventories: [:]),
            interface: interface
        )
        let finished = expectation(description: "unsupported transport")
        operation.start(withOutput: nil, completion: { success, _, error in
            XCTAssertFalse(success)
            XCTAssertNotNil(error)
            XCTAssertEqual(interface.calls, 0)
            finished.fulfill()
        })
        wait(for: [finished], timeout: 5)
    }

    func testReadingOriginalFileProducesASafePlanAndNeverRunsItsRuby() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = directory.appendingPathComponent("Brewfile")
        try "brew 'git'".write(to: file, atomically: true, encoding: .utf8)
        let plan = try BPBrewfilePlan.plan(with: file, inventories: [:])
        try "system('unsafe')".write(to: file, atomically: true, encoding: .utf8)
        let snapshot = try plan.createSnapshot()
        XCTAssertNotEqual(snapshot, file)
        XCTAssertEqual(try String(contentsOf: snapshot, encoding: .utf8), "brew 'git'\n")
        let unsafePlan = try BPBrewfilePlan.plan(with: file, inventories: [:])
        XCTAssertFalse(unsafePlan.canInstall)
        XCTAssertNil(try? BPBrewfilePlan.plan(with: directory, inventories: [:]))
        BPBrewfilePlan.removeSnapshot(snapshot)
        try? FileManager.default.removeItem(at: directory)
    }

    func testImportRunsOffMainDeliversOnMainAndRetainsSnapshotUntilCancelledCommandExits() {
        let interface = CB151ImportInterface(uniqueInstance: ())
        interface.releaseCommand = DispatchSemaphore(value: 0)
        let operation = BPBrewfileImportOperation(
            plan: BPBrewfilePlan.plan(withString: "brew 'git'", inventories: [:]),
            interface: interface
        )
        let entered = expectation(description: "entered")
        let output = expectation(description: "output")
        let finished = expectation(description: "finished")
        interface.entered = { entered.fulfill() }
        operation.start(
            withOutput: { chunk in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertEqual(chunk, "fixture output")
                output.fulfill()
            },
            completion: { success, cancelled, _ in
                XCTAssertTrue(Thread.isMainThread)
                XCTAssertFalse(success)
                XCTAssertTrue(cancelled)
                XCTAssertFalse(operation.running)
                let snapPath = (interface.snapshotPath as String?) ?? ""
                XCTAssertFalse(FileManager.default.fileExists(atPath: snapPath))
                finished.fulfill()
            }
        )
        wait(for: [entered, output], timeout: 5)
        operation.cancel()
        XCTAssertTrue(operation.running)
        let snapPath = (interface.snapshotPath as String?) ?? ""
        XCTAssertTrue(FileManager.default.fileExists(atPath: snapPath))
        operation.start(withOutput: nil, completion: nil)
        interface.releaseCommand?.signal()
        wait(for: [finished], timeout: 5)
        XCTAssertEqual(interface.calls, 1)
    }

    func testCancelledOrUnsupportedImportNeverStartsACommand() {
        for cancel in [true, false] {
            let interface = CB151ImportInterface(uniqueInstance: ())
            let plan = BPBrewfilePlan.plan(
                withString: cancel ? "brew 'git'" : "system('unsafe')",
                inventories: [:]
            )
            let operation = BPBrewfileImportOperation(plan: plan, interface: interface)
            if cancel {
                operation.cancel()
            }
            let finished = expectation(description: "not started")
            operation.start(withOutput: nil, completion: { success, _, _ in
                XCTAssertFalse(success)
                finished.fulfill()
            })
            wait(for: [finished], timeout: 5)
            XCTAssertEqual(interface.calls, 0)
        }
    }

    func testLiteralPlanPreservesTypesCommentsAndCRLFWithoutExecutingRuby() {
        let plan = BPBrewfilePlan.plan(
            withString: "# exported\r\ntap 'homebrew/cask'\r\nbrew \"git\" # comment\r\ncask 'firefox'\r\nmas \"Example App\", id: 123\r\nvscode 'publisher.extension'\r\n",
            inventories: ["brew": ["git"], "cask": [], "tap": ["homebrew/cask"]]
        )
        XCTAssertTrue(plan.canInstall)
        XCTAssertEqual(plan.entries.count, 5)
        XCTAssertEqual(plan.entries.map { $0.kind }, ["tap", "brew", "cask", "mas", "vscode"])
        XCTAssertEqual(plan.entries.map { $0.status }, ["Installed", "Installed", "Missing", "Not checked", "Not checked"])
        XCTAssertTrue(plan.canonicalContents?.contains("mas 'Example App', id: 123\n") == true)
    }

    func testAnyUnsupportedLineBlocksTheWholePlanWithLineDiagnostic() {
        let unsupportedLines = [
            "system('touch /tmp/unsafe')",
            "brew ENV['PACKAGE']",
            "brew \"#{system('x')}\"",
            "brew 'git', restart_service: true",
            "brew 'git'; system('x')",
            "brew '../git'",
            "brew '-help'",
            "mas 'App', id: 0",
            "cask 'app' do",
            "brew 'git\\n'",
            "brew 'git'\u{2028}system('x')"
        ]
        for line in unsupportedLines {
            let plan = BPBrewfilePlan.plan(withString: "brew 'git'\n" + line, inventories: [:])
            XCTAssertFalse(plan.canInstall, line)
            XCTAssertEqual(plan.diagnostics.count, 1, line)
            XCTAssertTrue(plan.diagnostics.first?.contains("2") == true, line)
            XCTAssertNil(plan.canonicalContents)
            XCTAssertNil(try? plan.createSnapshot())
        }
    }

    func testInventoryNamespacesAndUnknownQualifiedIdentityRemainHonest() {
        let plan = BPBrewfilePlan.plan(
            withString: "brew 'same'\ncask 'same'\nbrew 'owner/tap/same'\ntap 'owner/tap'",
            inventories: ["brew": ["same"]]
        )
        XCTAssertEqual(plan.entries.map { $0.status }, ["Installed", "Not checked", "Not checked", "Not checked"])
        XCTAssertFalse(BPBrewfilePlan.plan(withString: "# empty", inventories: [:]).canInstall)
    }

    func testSnapshotIsCanonicalPrivateAndIndependentOfMutableInput() throws {
        let source = NSMutableString(string: "brew \"git\" # ignored")
        let plan = BPBrewfilePlan.plan(withString: source as String, inventories: [:])
        source.setString("system('unsafe')")
        let snapshot = try plan.createSnapshot()
        XCTAssertEqual(try String(contentsOf: snapshot, encoding: .utf8), "brew 'git'\n")
        let attributes = try FileManager.default.attributesOfItem(atPath: snapshot.deletingLastPathComponent().path)
        XCTAssertEqual((attributes[FileAttributeKey.posixPermissions] as? NSNumber)?.intValue, 0o700)
        BPBrewfilePlan.removeSnapshot(snapshot)
        XCTAssertFalse(FileManager.default.fileExists(atPath: snapshot.path))
    }

    private func accepts(_ name: String) -> Bool {
        BPBrewfile.isBrewfileURL(URL(fileURLWithPath: ("/tmp" as NSString).appendingPathComponent(name)))
    }

    // MARK: - What counts

    func testDefaultFilenameKeepsTheCanonicalHomebrewName() {
        XCTAssertEqual(BPBrewfile.defaultFilename(), "Brewfile")
        XCTAssertTrue(accepts(BPBrewfile.defaultFilename()))
    }

    func testTheCanonicalNameIsAccepted() {
        XCTAssertTrue(accepts("Brewfile"))
    }

    func testTheNameIsMatchedCaseInsensitively() {
        XCTAssertTrue(accepts("brewfile"))
        XCTAssertTrue(accepts("BREWFILE"))
    }

    func testAQualifiedBrewfileIsAccepted() {
        XCTAssertTrue(accepts("work.Brewfile"))
        XCTAssertTrue(accepts("personal.brewfile"))
    }

    // MARK: - What does not

    func testTheLockFileIsRejected() {
        XCTAssertFalse(accepts("Brewfile.lock.json"))
    }

    func testAnUnrelatedNameIsRejected() {
        XCTAssertFalse(accepts("README"))
        XCTAssertFalse(accepts("Brewfile.txt"))
        XCTAssertFalse(accepts("Podfile"))
        XCTAssertFalse(accepts("my-brewfile-notes.md"))
    }

    func testNonFileAndMissingURLsAreRejected() {
        XCTAssertFalse(BPBrewfile.isBrewfileURL(nil))
        XCTAssertFalse(BPBrewfile.isBrewfileURL(URL(string: "https://example.com/Brewfile")))
    }

    // MARK: - Filtering a drop

    func testFilteringKeepsOnlyBrewfilesInOrder() {
        let urls = [
            URL(fileURLWithPath: "/tmp/README"),
            URL(fileURLWithPath: "/tmp/work.Brewfile"),
            URL(fileURLWithPath: "/tmp/Brewfile.lock.json"),
            URL(fileURLWithPath: "/tmp/Brewfile")
        ]

        let filtered = BPBrewfile.brewfileURLs(from: urls)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertEqual(filtered.first?.lastPathComponent, "work.Brewfile")
        XCTAssertEqual(filtered.last?.lastPathComponent, "Brewfile")
    }

    func testFilteringNothingYieldsNothingRatherThanNil() {
        XCTAssertEqual(BPBrewfile.brewfileURLs(from: []), [])
        XCTAssertEqual(BPBrewfile.brewfileURLs(from: nil), [])
    }
}
