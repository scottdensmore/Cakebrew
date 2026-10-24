//
//  BPCancelReloadTests.swift
//  CakebrewTests
//

import AppKit
import XCTest

@MainActor
final class BPCancelReloadTests: XCTestCase, @unchecked Sendable {

    // MARK: - When the toolbar offers Cancel

    func testCancelIsAbsentWhenNoReloadIsRunning() {
        let identifiers = BPToolbar.defaultItemIdentifiers(showingCancel: false)

        XCTAssertFalse(identifiers.contains(BPToolbar.cancelReloadItemIdentifier()))
    }

    func testCancelAppearsExactlyOnceWhileReloading() {
        let identifiers = BPToolbar.defaultItemIdentifiers(showingCancel: true)
        let count = identifiers.filter { $0 == BPToolbar.cancelReloadItemIdentifier() }.count

        XCTAssertEqual(count, 1, "a second insert would leave a duplicate behind: \(identifiers)")
    }

    func testShowingCancelAddsNothingElseAndRemovesNothing() {
        let without = BPToolbar.defaultItemIdentifiers(showingCancel: false)
        let with = BPToolbar.defaultItemIdentifiers(showingCancel: true)

        XCTAssertEqual(with.count, without.count + 1)

        var stripped = with
        stripped.removeAll { $0 == BPToolbar.cancelReloadItemIdentifier() }

        XCTAssertEqual(stripped, without, "showing Cancel reordered or dropped an item")
    }

    func testTheInsertionIndexMatchesTheListedPosition() {
        let with = BPToolbar.defaultItemIdentifiers(showingCancel: true)

        XCTAssertEqual(
            with.firstIndex(of: BPToolbar.cancelReloadItemIdentifier()),
            Int(BPToolbar.cancelReloadItemIndex())
        )
    }

    // MARK: - What cancelling does

    func testCancellingAReloadStopsItPublishing() {
        let manager = BPHomebrewManager.sharedManager()
        let generation = manager.currentReloadGeneration

        manager.cancelReload()

        XCTAssertNotEqual(
            manager.currentReloadGeneration,
            generation,
            "a cancelled reload must not be allowed to publish"
        )
    }
}
