//
//  BPServiceDetailsTests.swift
//  CakebrewTests
//

import ObjectiveC
import XCTest

final class BPServiceDetailsTests: XCTestCase, @unchecked Sendable {

    func testRealServiceListUsesCleanJSONAndRejectsFailedPartialOutput() {
        let interface = BPServiceInfoShellInterface(uniqueInstance: ())
        interface.brewTransport = .direct
        interface.setValue("/bin/sh", forKey: "path_shell")
        interface.fixtureCommand = "printf 'banner\\n+++++Cakebrew+++++\\n[{\"name\":\"redis\",\"status\":\"started\"}]\\n'"
        XCTAssertEqual(interface.listServices().first?.name, "redis")
        interface.fixtureCommand = "printf '+++++Cakebrew+++++\\n[{\"name\":\"redis\"}]\\n'; exit 7"
        XCTAssertEqual(interface.listServices().count, 0)
    }

    func testLoadedFileIsRetainedSeparatelyFromFormulaServiceFile() {
        let result = BPServiceDetails.details(
            forName: "redis",
            output: "[{\"name\":\"redis\",\"file\":\"/opt/redis.plist\",\"loaded_file\":\"~/Library/LaunchAgents/redis.plist\"}]",
            succeeded: true
        )
        XCTAssertEqual(result.serviceFile, "/opt/redis.plist")
        XCTAssertEqual(result.loadedFile, "~/Library/LaunchAgents/redis.plist")
    }

    func testRealTaskKeepsJSONCleanPreservesStatusAndDoesNotReplaceCancelTarget() {
        let interface = BPServiceInfoShellInterface(uniqueInstance: ())
        interface.brewTransport = .direct
        interface.setValue("/bin/sh", forKey: "path_shell")
        let existing = BPTask(path: "/usr/bin/true", arguments: [])
        interface.setValue(existing, forKey: "currentOperationTask")
        interface.fixtureCommand = "printf 'login banner\\n+++++Cakebrew+++++\\n[{\"name\":\"redis\"}]\\n'"
        var result = interface.serviceDetails(forName: "redis")
        XCTAssertTrue(result.available)
        XCTAssertEqual(result.rawOutput, "[{\"name\":\"redis\"}]\n")
        XCTAssertEqual(interface.value(forKey: "currentOperationTask") as? BPTask, existing)
        interface.fixtureCommand = "printf '+++++Cakebrew+++++\\nError: fixture failure\\n'; exit 7"
        result = interface.serviceDetails(forName: "redis")
        XCTAssertFalse(result.available)
        XCTAssertEqual(result.rawOutput, "Error: fixture failure\n")
        XCTAssertEqual(interface.value(forKey: "currentOperationTask") as? BPTask, existing)
    }

    func testUnsupportedHelperTransportCannotDispatchOrHijackAnOperation() {
        let interface = BPServiceInfoFixtureInterface(uniqueInstance: ())
        interface.brewTransport = .helper
        interface.fixture = "[{\"name\":\"redis\"}]"
        interface.succeeded = true
        let result = interface.serviceDetails(forName: "redis")
        XCTAssertFalse(result.available)
        XCTAssertGreaterThan(result.rawOutput.count, 0)
        XCTAssertNil(interface.arguments)
    }

    func testMockOwnsTheReadOnlyServiceDetailBoundary() {
        let mock: AnyClass? = NSClassFromString("BPMockHomebrewInterface")
        let real = class_getInstanceMethod(BPHomebrewInterface.self, #selector(BPHomebrewInterface.serviceDetails(forName:)))
        let replacement = class_getInstanceMethod(mock, #selector(BPHomebrewInterface.serviceDetails(forName:)))
        XCTAssertNotNil(real)
        XCTAssertNotNil(replacement)
        if let real, let replacement {
            XCTAssertNotEqual(method_getImplementation(real), method_getImplementation(replacement))
        }
    }

    func testReadOnlyTransportPreservesFailureAndRequestsCleanOutput() {
        let interface = BPServiceInfoFixtureInterface(uniqueInstance: ())
        interface.fixture = "[{\"name\":\"redis\"}]"
        interface.succeeded = true
        XCTAssertTrue(interface.serviceDetails(forName: "redis").available)
        XCTAssertEqual(interface.arguments as? [String], ["services", "info", "--json", "redis"])
        XCTAssertTrue(interface.readOnly)
        XCTAssertFalse(interface.footer)
        interface.succeeded = false
        interface.fixture = "Error: unavailable\nfull diagnostic"
        let result = interface.serviceDetails(forName: "redis")
        XCTAssertFalse(result.available)
        XCTAssertEqual(result.rawOutput, interface.fixture as String?)
    }

    func testFailuresRetainRawOutputAndDoNotAcceptAnotherService() {
        let outputs = [
            "Error: unavailable",
            "[]",
            "{}",
            "[null]",
            "[{\"name\":\"other\"}]",
            "[{\"name\":\"redis\"},{\"name\":\"redis\"}]"
        ]
        for output in outputs {
            let result = BPServiceDetails.details(forName: "redis", output: output, succeeded: true)
            XCTAssertFalse(result.available)
            XCTAssertEqual(result.rawOutput, output)
        }
        XCTAssertFalse(BPServiceDetails.details(forName: "redis", output: "[{\"name\":\"redis\"}]", succeeded: false).available)
    }

    func testMissingAndWrongTypedMetadataRemainUnavailable() {
        for pid in ["null", "true", "0", "-1", "1.5", "\"123\""] {
            let json = "[{\"name\":\"redis\",\"pid\":\(pid),\"user\":null,\"file\":3,\"log_path\":[],\"error_log_path\":null,\"exit_code\":true,\"unknown\":{}}]"
            let result = BPServiceDetails.details(forName: "redis", output: json, succeeded: true)
            XCTAssertTrue(result.available)
            XCTAssertNil(result.service?.pid)
            XCTAssertNil(result.service?.user)
            XCTAssertNil(result.serviceFile)
            XCTAssertNil(result.logPath)
            XCTAssertNil(result.errorLogPath)
            XCTAssertNil(result.exitCode)
        }
    }

    func testLocalFileValidationRejectsUnsafePathsAndRevalidatesDeletedFiles() throws {
        let directory = (NSTemporaryDirectory() as NSString).appendingPathComponent(UUID().uuidString)
        let files = FileManager.default
        try files.createDirectory(atPath: directory, withIntermediateDirectories: true, attributes: nil)
        let path = (directory as NSString).appendingPathComponent("service log.txt")
        try "fixture".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(BPServiceDetails.readableFileURL(forPath: path)?.path, (path as NSString).resolvingSymlinksInPath)
        let link = (directory as NSString).appendingPathComponent("link")
        try files.createSymbolicLink(atPath: link, withDestinationPath: path)
        XCTAssertEqual(BPServiceDetails.readableFileURL(forPath: link)?.path, (path as NSString).resolvingSymlinksInPath)
        let invalidPaths = [
            "",
            "relative.log",
            "file:///etc/hosts",
            "https://example.com/log",
            "//server/share",
            "~another/log",
            "/dev/null",
            "/tmp",
            "/etc/hosts\n"
        ]
        for invalid in invalidPaths {
            XCTAssertNil(BPServiceDetails.readableFileURL(forPath: invalid), invalid)
        }
        try files.removeItem(atPath: path)
        XCTAssertNil(BPServiceDetails.readableFileURL(forPath: path))
        XCTAssertNil(BPServiceDetails.readableFileURL(forPath: link))
        try files.removeItem(atPath: directory)
    }

    func testParsesSelectedServiceMetadata() {
        let json = "[{\"name\":\"redis\",\"status\":\"started\",\"pid\":123,\"user\":\"mockuser\",\"file\":\"/tmp/service.plist\",\"log_path\":\"/tmp/service.log\",\"error_log_path\":\"/tmp/service.log\",\"exit_code\":0}]"
        let details = BPServiceDetails.details(forName: "redis", output: json, succeeded: true)
        XCTAssertTrue(details.available)
        XCTAssertEqual(details.service?.name, "redis")
        XCTAssertEqual(details.service?.pid, NSNumber(value: 123))
        XCTAssertEqual(details.service?.user, "mockuser")
        XCTAssertEqual(details.serviceFile, "/tmp/service.plist")
        XCTAssertEqual(details.logPath, "/tmp/service.log")
        XCTAssertEqual(details.errorLogPath, details.logPath)
        XCTAssertEqual(details.exitCode, NSNumber(value: 0))
        XCTAssertEqual(details.rawOutput, json)
    }
}
