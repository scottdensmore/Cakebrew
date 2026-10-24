//
//  BPCleanupPreviewTests.swift
//  CakebrewTests
//

import Foundation
import XCTest

final class BPCleanupPreviewTests: XCTestCase, @unchecked Sendable {

    // MARK: - Counting removals

    func testCountsEveryWouldRemoveLine() {
        let output =
            "Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz (1.5MB)\n" +
            "Would remove: /opt/homebrew/Cellar/git/2.39.0 (1,234 files, 45.6MB)\n" +
            "Would remove: /Users/x/Library/Caches/Homebrew/curl--8.0.0.tar.gz (2.1MB)\n" +
            "==> This operation would free approximately 49.2MB of disk space.\n"

        let preview = BPCleanupPreview.preview(fromOutput: output)

        XCTAssertEqual(preview.itemCount, 3)
    }

    func testKeepsThePathsInOrderWithoutTheSizeSuffix() {
        let output =
            "Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz (1.5MB)\n" +
            "Would remove: /opt/homebrew/Cellar/git/2.39.0 (1,234 files, 45.6MB)\n"

        let preview = BPCleanupPreview.preview(fromOutput: output)

        XCTAssertEqual(
            preview.paths,
            [
                "/Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz",
                "/opt/homebrew/Cellar/git/2.39.0"
            ]
        )
    }

    func testIgnoresLinesThatAreNotRemovals() {
        let output =
            "==> Autoremoving 0 unneeded formulae...\n" +
            "Warning: Skipping mockgit: most recent version 2.40.0 not installed\n" +
            "Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz (1.5MB)\n" +
            "Pruned 0 symbolic links and 2 directories from /opt/homebrew\n"

        let preview = BPCleanupPreview.preview(fromOutput: output)

        XCTAssertEqual(preview.itemCount, 1)
    }

    // MARK: - The reclaimable total

    func testReadsTheReclaimableTotalInMegabytes() {
        let output = "==> This operation would free approximately 49.2MB of disk space.\n"

        let preview = BPCleanupPreview.preview(fromOutput: output)

        XCTAssertEqual(preview.reclaimableBytes, UInt64(49.2 * 1024 * 1024))
    }

    func testReadsGigabytesKilobytesAndBareBytes() {
        XCTAssertEqual(
            BPCleanupPreview.preview(fromOutput: "==> This operation would free approximately 1.4GB of disk space.").reclaimableBytes,
            UInt64(1.4 * 1024 * 1024 * 1024)
        )

        XCTAssertEqual(
            BPCleanupPreview.preview(fromOutput: "==> This operation would free approximately 512.0KB of disk space.").reclaimableBytes,
            UInt64(512.0 * 1024)
        )

        XCTAssertEqual(
            BPCleanupPreview.preview(fromOutput: "==> This operation would free approximately 900B of disk space.").reclaimableBytes,
            900
        )
    }

    func testNothingToCleanIsEmpty() {
        let preview = BPCleanupPreview.preview(fromOutput: "")

        XCTAssertEqual(preview.itemCount, 0)
        XCTAssertEqual(preview.reclaimableBytes, 0)
        XCTAssertTrue(preview.empty)
    }

    func testRemovalsWithoutASummaryLineAreStillNotEmpty() {
        let output = "Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz\n"

        let preview = BPCleanupPreview.preview(fromOutput: output)

        XCTAssertEqual(preview.itemCount, 1)
        XCTAssertEqual(preview.reclaimableBytes, 0)
        XCTAssertFalse(preview.empty)
    }

    // MARK: - The dry-run command

    func testTheDryRunCommandPassesDryRun() {
        XCTAssertEqual(BPHomebrewInterface.argumentsForCleanupDryRun(), ["cleanup", "--dry-run"])
    }

    // MARK: - Robustness

    func testMalformedInputParsesToEmptyRatherThanThrowing() {
        XCTAssertTrue(BPCleanupPreview.preview(fromOutput: nil).empty)
        XCTAssertTrue(BPCleanupPreview.preview(fromOutput: "\n\n\n").empty)
        XCTAssertEqual(
            BPCleanupPreview.preview(fromOutput: "==> This operation would free approximately QUITE A LOT of disk space.").reclaimableBytes,
            0
        )
    }
}
