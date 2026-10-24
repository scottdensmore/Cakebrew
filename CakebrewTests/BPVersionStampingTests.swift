//
//  BPVersionStampingTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPVersionStampingTests: XCTestCase, @unchecked Sendable {

    private func contentsOfRepoFile(_ relativePath: String) -> String {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = repoRoot.appendingPathComponent(relativePath).path
        let contents = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        XCTAssertFalse(contents.isEmpty, "could not read \(path)")
        return contents
    }

    private func value(forPlistKey key: String, in plist: String) -> String {
        let pattern = "<key>\(key)</key>\\s*<string>([^<]*)</string>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            XCTFail("invalid regex")
            return ""
        }
        let nsPlist = plist as NSString
        guard let match = regex.firstMatch(in: plist, options: [], range: NSRange(location: 0, length: nsPlist.length)) else {
            XCTFail("\(key) not found")
            return ""
        }
        return nsPlist.substring(with: match.range(at: 1))
    }

    func testTheAppDerivesBothVersionsFromBuildSettings() {
        let plist = contentsOfRepoFile("Cakebrew/Cakebrew-Info.plist")

        XCTAssertEqual(value(forPlistKey: "CFBundleShortVersionString", in: plist), "$(MARKETING_VERSION)")
        XCTAssertEqual(value(forPlistKey: "CFBundleVersion", in: plist), "$(CURRENT_PROJECT_VERSION)")
    }

    func testTheHelperDerivesBothVersionsFromBuildSettings() {
        let plist = contentsOfRepoFile("Cakebrew/Helper/CakebrewHelper-Info.plist")

        XCTAssertEqual(value(forPlistKey: "CFBundleShortVersionString", in: plist), "$(MARKETING_VERSION)")
        XCTAssertEqual(value(forPlistKey: "CFBundleVersion", in: plist), "$(CURRENT_PROJECT_VERSION)")
    }

    func testEveryTargetDefinesTheVersionSettingsItReferences() {
        let project = contentsOfRepoFile("Cakebrew.xcodeproj/project.pbxproj")

        let appAndHelperConfigurations = 4 // Debug + Release, app + helper
        XCTAssertGreaterThanOrEqual(count(of: "MARKETING_VERSION = ", in: project), appAndHelperConfigurations)
        XCTAssertGreaterThanOrEqual(count(of: "CURRENT_PROJECT_VERSION = ", in: project), appAndHelperConfigurations)
    }

    func testTheReleaseWorkflowStampsTheVersionFromTheTag() throws {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let workflowPath = repoRoot.appendingPathComponent(".github/workflows/release.yml").path
        try XCTSkipIf(
            !FileManager.default.fileExists(atPath: workflowPath),
            ".github/workflows/release.yml is not present in this checkout"
        )

        let workflow = contentsOfRepoFile(".github/workflows/release.yml")

        XCTAssertGreaterThan(
            count(of: "MARKETING_VERSION=", in: workflow),
            0,
            "the archive step should pass the version parsed from the tag"
        )
        XCTAssertGreaterThan(
            count(of: "CFBundleShortVersionString", in: workflow),
            0,
            "the export should be asserted against the tag before publishing"
        )
    }

    private func count(of needle: String, in haystack: String) -> Int {
        guard !needle.isEmpty else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }
}
