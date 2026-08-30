//
//  BPCleanupPreviewTests.m
//  CakebrewTests
//
//  Cleanup is the app's only destructive one-click action — it permanently
//  deletes cached downloads and old installed versions — and it was the only
//  action with no confirmation, while non-destructive install and pin
//  operations did confirm.
//
//  `brew cleanup --dry-run` says exactly what it would delete. Turning that
//  text into (count, bytes) is a pure string -> value transform, so it is the
//  seam worth testing: the sheet is only as honest as this parser.
//

#import <XCTest/XCTest.h>
#import "BPCleanupPreview.h"
#import "BPHomebrewInterface.h"

@interface BPCleanupPreviewTests : XCTestCase
@end

@implementation BPCleanupPreviewTests

#pragma mark - Counting removals

- (void)testCountsEveryWouldRemoveLine
{
	NSString *output =
		@"Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz (1.5MB)\n"
		@"Would remove: /opt/homebrew/Cellar/git/2.39.0 (1,234 files, 45.6MB)\n"
		@"Would remove: /Users/x/Library/Caches/Homebrew/curl--8.0.0.tar.gz (2.1MB)\n"
		@"==> This operation would free approximately 49.2MB of disk space.\n";

	BPCleanupPreview *preview = [BPCleanupPreview previewFromOutput:output];

	XCTAssertEqual(preview.itemCount, 3u);
}

/// The paths are what makes the sheet reviewable rather than a bare number.
- (void)testKeepsThePathsInOrderWithoutTheSizeSuffix
{
	NSString *output =
		@"Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz (1.5MB)\n"
		@"Would remove: /opt/homebrew/Cellar/git/2.39.0 (1,234 files, 45.6MB)\n";

	BPCleanupPreview *preview = [BPCleanupPreview previewFromOutput:output];

	XCTAssertEqualObjects(preview.paths, (@[ @"/Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz",
											 @"/opt/homebrew/Cellar/git/2.39.0" ]));
}

/// brew prints progress and warnings into the same stream; only the removal
/// lines are removals.
- (void)testIgnoresLinesThatAreNotRemovals
{
	NSString *output =
		@"==> Autoremoving 0 unneeded formulae...\n"
		@"Warning: Skipping mockgit: most recent version 2.40.0 not installed\n"
		@"Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz (1.5MB)\n"
		@"Pruned 0 symbolic links and 2 directories from /opt/homebrew\n";

	BPCleanupPreview *preview = [BPCleanupPreview previewFromOutput:output];

	XCTAssertEqual(preview.itemCount, 1u);
}

#pragma mark - The reclaimable total

- (void)testReadsTheReclaimableTotalInMegabytes
{
	NSString *output = @"==> This operation would free approximately 49.2MB of disk space.\n";

	BPCleanupPreview *preview = [BPCleanupPreview previewFromOutput:output];

	// brew's disk_usage_readable is 1024-based, so MB means MiB.
	XCTAssertEqual(preview.reclaimableBytes, (unsigned long long)(49.2 * 1024 * 1024));
}

- (void)testReadsGigabytesKilobytesAndBareBytes
{
	XCTAssertEqual([BPCleanupPreview previewFromOutput:
					@"==> This operation would free approximately 1.4GB of disk space."].reclaimableBytes,
				   (unsigned long long)(1.4 * 1024 * 1024 * 1024));

	XCTAssertEqual([BPCleanupPreview previewFromOutput:
					@"==> This operation would free approximately 512.0KB of disk space."].reclaimableBytes,
				   (unsigned long long)(512.0 * 1024));

	XCTAssertEqual([BPCleanupPreview previewFromOutput:
					@"==> This operation would free approximately 900B of disk space."].reclaimableBytes,
				   900ull);
}

/// The whole point of the preview is to be able to say "nothing to do" without
/// deleting anything first.
- (void)testNothingToCleanIsEmpty
{
	BPCleanupPreview *preview = [BPCleanupPreview previewFromOutput:@""];

	XCTAssertEqual(preview.itemCount, 0u);
	XCTAssertEqual(preview.reclaimableBytes, 0ull);
	XCTAssertTrue(preview.isEmpty);
}

/// A run can find files it cannot size, so brew omits the summary line. Items
/// without a total is a real state, and it is not "nothing to do".
- (void)testRemovalsWithoutASummaryLineAreStillNotEmpty
{
	NSString *output = @"Would remove: /Users/x/Library/Caches/Homebrew/wget--1.21.3.tar.gz\n";

	BPCleanupPreview *preview = [BPCleanupPreview previewFromOutput:output];

	XCTAssertEqual(preview.itemCount, 1u);
	XCTAssertEqual(preview.reclaimableBytes, 0ull);
	XCTAssertFalse(preview.isEmpty);
}

#pragma mark - The dry-run command

/// The preview is only trustworthy if it never deletes. --dry-run is the whole
/// safety property, so it is asserted rather than assumed.
- (void)testTheDryRunCommandPassesDryRun
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForCleanupDryRun],
						  (@[ @"cleanup", @"--dry-run" ]));
}

#pragma mark - Robustness

/// Never crash on whatever a future brew prints.
- (void)testMalformedInputParsesToEmptyRatherThanThrowing
{
	XCTAssertTrue([BPCleanupPreview previewFromOutput:nil].isEmpty);
	XCTAssertTrue([BPCleanupPreview previewFromOutput:@"\n\n\n"].isEmpty);
	XCTAssertEqual([BPCleanupPreview previewFromOutput:
					@"==> This operation would free approximately QUITE A LOT of disk space."].reclaimableBytes,
				   0ull);
}

@end
