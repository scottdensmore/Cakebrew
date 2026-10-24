//
//  BPLoadingStatusTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPLoadingStatusTests: XCTestCase, @unchecked Sendable {

    private var reloadedModes: [BPListMode] {
        [
            .installed,
            .outdated,
            .all,
            .leaves,
            .pinned,
            .repositories,
            .installedCasks,
            .outdatedCasks,
            .allCasks
        ]
    }

    // MARK: - A step for every list

    func testEveryReloadedListHasItsOwnStatusKey() {
        var keys = Set<String>()

        for mode in reloadedModes {
            let key = BPLoadingStatus.localizationKey(forListMode: mode.rawValue)

            XCTAssertNotNil(key, "mode \(mode.rawValue) has no status")
            if let key {
                XCTAssertFalse(keys.contains(key), "mode \(mode.rawValue) reuses the status of an earlier list")
                keys.insert(key)
            }
        }
    }

    func testSearchHasNoStatus() {
        XCTAssertNil(BPLoadingStatus.localizationKey(forListMode: BPListMode.search.rawValue))
    }

    // MARK: - The keys really ship

    func testEveryStatusKeyIsInTheStringsFile() {
        let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let path = repoRoot.appendingPathComponent("Cakebrew/en.lproj/Localizable.strings").path
        let english = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""

        XCTAssertFalse(english.isEmpty, "could not read en.lproj at \(path)")

        for mode in reloadedModes {
            guard let key = BPLoadingStatus.localizationKey(forListMode: mode.rawValue) else {
                XCTFail("missing key for \(mode.rawValue)")
                continue
            }
            let quoted = "\"\(key)\" ="
            XCTAssertTrue(english.contains(quoted), "\(key) is not in en.lproj")
        }

        XCTAssertTrue(english.contains("\"Loading_Status_Default\" ="))
        XCTAssertTrue(english.contains("\"Loading_Cancel\" ="))
    }

    // MARK: - Which steps are worth warning about

    func testOnlyTheCatalogFetchesAreMarkedSlow() {
        XCTAssertTrue(BPLoadingStatus.isSlowListMode(BPListMode.all.rawValue))
        XCTAssertTrue(BPLoadingStatus.isSlowListMode(BPListMode.allCasks.rawValue))

        XCTAssertFalse(BPLoadingStatus.isSlowListMode(BPListMode.installed.rawValue))
        XCTAssertFalse(BPLoadingStatus.isSlowListMode(BPListMode.outdated.rawValue))
        XCTAssertFalse(BPLoadingStatus.isSlowListMode(BPListMode.pinned.rawValue))
        XCTAssertFalse(BPLoadingStatus.isSlowListMode(BPListMode.search.rawValue))
    }
}
