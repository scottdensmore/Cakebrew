//
//  BPHomebrewRecoveryTests.swift
//  CakebrewTests
//

import ObjectiveC
import XCTest

final class BPHomebrewRecoveryTests: XCTestCase, BPHomebrewManagerDelegate, @unchecked Sendable {
    var manager: BPRecoveryFixtureManager!
    var onResult: ((Bool) -> Void)?
    var onFinish: (() -> Void)?
    var finishes: UInt = 0

    override func setUp() {
        super.setUp()
        manager = BPRecoveryFixtureManager(uniqueInstance: ())
        manager.fixture = BPRecoveryFixtureInterface(uniqueInstance: ())
        manager.delegate = self
    }

    func homebrewManager(_ manager: BPHomebrewManager, shouldDisplayNoBrewMessage missing: Bool) {
        XCTAssertTrue(Thread.isMainThread)
        onResult?(missing)
    }

    func homebrewManagerFinishedUpdating(_ manager: BPHomebrewManager) {
        finishes += 1
        onFinish?()
    }

    func homebrewManager(_ manager: BPHomebrewManager, didUpdateSearchResults results: [Any]?) {}

    private func discoveryOutput(_ path: String) -> String {
        "Login banner\n+++++Cakebrew Discovery+++++\n\(path)\n+++++Cakebrew Discovery End+++++\n"
    }

    func testNonzeroExitCannotTurnAnErrorMessageIntoAnInstallation() {
        XCTAssertEqual(BPHomebrewInterface.discoveryResult(forOutput: "brew not found\n", exitStatus: 1), .checkFailed)
        XCTAssertEqual(BPHomebrewInterface.discoveryResult(forOutput: discoveryOutput("/usr/bin/true"), exitStatus: 2), .checkFailed)
    }

    func testMissingCommandIsDistinctFromAnUnusableCheck() {
        XCTAssertEqual(BPHomebrewInterface.discoveryResult(forOutput: discoveryOutput(""), exitStatus: 1), .missing)
        XCTAssertEqual(BPHomebrewInterface.discoveryResult(forOutput: "", exitStatus: 0), .checkFailed)
    }

    func testOnlyAnAbsoluteExecutableFileInsideTheMarkersIsAvailable() {
        XCTAssertEqual(BPHomebrewInterface.discoveryResult(forOutput: discoveryOutput("/usr/bin/true"), exitStatus: 0), .available)
        for path in ["brew", "brew not found", "/usr/bin", "/etc/shells", "/no/such/brew", "/usr/bin/true\n/usr/bin/false"] {
            XCTAssertEqual(BPHomebrewInterface.discoveryResult(forOutput: discoveryOutput(path), exitStatus: 0), .checkFailed, path)
        }
    }

    func testOfficialInstallationURLIsHTTPS() {
        XCTAssertEqual(BPHomebrewInterface.installationURL().absoluteString, "https://brew.sh")
    }

    func testMockOverridesTheEntireDiscoveryExecutionBoundary() {
        let mock: AnyClass? = NSClassFromString("BPMockHomebrewInterface")
        XCTAssertNotNil(mock)
        XCTAssertNotEqual(
            class_getInstanceMethod(mock, #selector(BPHomebrewInterface.discoverHomebrew)),
            class_getInstanceMethod(BPHomebrewInterface.self, #selector(BPHomebrewInterface.discoverHomebrew))
        )
    }

    func testRecoveryViewWiresBothActionsAndWrapsItsMessage() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("Cakebrew/Views/Base.lproj/Disabled.xib")
        let document = try XMLDocument(contentsOf: url, options: [])
        for selector in ["retry:", "openInstallationInstructions:"] {
            let query = "//button/connections/action[@selector='\(selector)' and @target='-2']"
            XCTAssertEqual(try document.nodes(forXPath: query).count, 1)
        }
        XCTAssertEqual(try document.nodes(forXPath: "//textFieldCell[@id='sdR-dW-MDv' and @wraps='YES']").count, 1)
    }

    func testDiscoveryExecutesTheTaskAndUsesItsStatusAndMarkedOutput() throws {
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let files = FileManager.default
        try files.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        let interface = BPRecoveryShellInterface(uniqueInstance: ())
        let shellPath = (directory as NSString).appendingPathComponent("shell")
        interface.shell = shellPath as NSString
        defer {
            try? files.removeItem(atPath: directory)
        }

        for status in [0, 2] {
            let script = "#!/bin/sh\nprintf 'Login banner\\n+++++Cakebrew Discovery+++++\\n/usr/bin/true\\n+++++Cakebrew Discovery End+++++\\n'\nexit \(status)\n"
            try script.write(toFile: shellPath, atomically: true, encoding: .utf8)
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shellPath)
            XCTAssertEqual(interface.discoverHomebrew(), status == 0 ? .available : .checkFailed)
        }
        interface.shell = nil
        XCTAssertEqual(interface.discoverHomebrew(), .invalidShell)
    }

    func testDiscoveryCommandFindsAnExecutableWithoutRunningItAndHandlesMissingPATH() throws {
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let files = FileManager.default
        try files.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        let interface = BPRecoveryShellInterface(uniqueInstance: ())
        let shellPath = (directory as NSString).appendingPathComponent("shell")
        interface.shell = shellPath as NSString
        let brew = (directory as NSString).appendingPathComponent("brew")
        defer {
            try? files.removeItem(atPath: directory)
        }

        // Execute the production command ($3 after -l -c) with a fixture-only
        // PATH. A login banner must not pollute discovery. The fake brew exits
        // 97 if run: discovering it must not execute it.
        let wrapper = "#!/bin/sh\nprintf 'fixture login banner\\n'\nPATH='\(directory)'; export PATH\nexec /bin/sh -c \"$3\"\n"
        try wrapper.write(toFile: shellPath, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: shellPath)
        try "#!/bin/sh\nexit 97\n".write(toFile: brew, atomically: true, encoding: .utf8)
        try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: brew)
        XCTAssertEqual(interface.discoverHomebrew(), .available)
        try files.removeItem(atPath: brew)
        XCTAssertEqual(interface.discoverHomebrew(), .missing)
    }

    func testFailedDiscoveryHasNoListFanoutAndPersistentRetryChecksAgain() {
        manager.fixture?.nextResult = .missing
        for attempt: UInt in 1...2 {
            let failed = expectation(description: "discovery failed")
            onResult = { missing in
                XCTAssertTrue(missing)
                failed.fulfill()
            }
            manager.retryHomebrewDiscovery()
            wait(for: [failed], timeout: 3)
            XCTAssertEqual(manager.discoveryResult, .missing)
            XCTAssertFalse(manager.checkingHomebrew)
            XCTAssertEqual(manager.fixture?.discoveryCalls, attempt)
            XCTAssertEqual(manager.fixture?.listCalls, 0)
            XCTAssertEqual(finishes, 0)
        }
    }

    func testRetryIsSingleFlightAndRecoveryRunsExactlyOneNormalPipeline() {
        manager.fixture?.nextResult = .missing
        let failed = expectation(description: "initial failure")
        onResult = { missing in
            XCTAssertTrue(missing)
            failed.fulfill()
        }
        manager.reloadFromInterface(rebuildingCache: false)
        wait(for: [failed], timeout: 3)

        let holdSemaphore = DispatchSemaphore(value: 0)
        manager.fixture?.nextResult = .available
        manager.fixture?.holdDiscovery = holdSemaphore
        let checking = expectation(description: "retry begins off-main")
        manager.fixture?.onDiscovery = {
            XCTAssertFalse(Thread.isMainThread)
            checking.fulfill()
        }
        let recovered = expectation(description: "available")
        onResult = { missing in
            XCTAssertFalse(missing)
            recovered.fulfill()
        }
        let finished = expectation(description: "one pipeline finished")
        onFinish = {
            finished.fulfill()
        }
        manager.retryHomebrewDiscovery()
        wait(for: [checking], timeout: 3)
        XCTAssertTrue(manager.checkingHomebrew)
        manager.retryHomebrewDiscovery()
        manager.reloadFromInterface(rebuildingCache: true)
        XCTAssertEqual(manager.fixture?.discoveryCalls, 2)
        holdSemaphore.signal()
        wait(for: [recovered, finished], timeout: 3)
        XCTAssertEqual(manager.discoveryResult, .available)
        XCTAssertFalse(manager.checkingHomebrew)
        XCTAssertEqual(manager.fixture?.discoveryCalls, 2)
        XCTAssertEqual(manager.fixture?.listCalls, 11)
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(manager.installedFormulae?.first?.name, "recovered")
    }
}
