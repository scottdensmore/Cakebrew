//
//  BPBrewfileTests.m
//  CakebrewTests
//
//  Brewfiles are first class to this app — Tools ▸ Export / Import Brew
//  Installation — but the bundle declared no document types, so one in Finder
//  had no relationship to Cakebrew at all: not openable with it, not droppable
//  on it.
//
//  Deciding what counts as a Brewfile is the part worth testing. Too narrow and
//  the feature does not fire on files people really have; too broad and
//  Cakebrew offers to run `brew bundle` against arbitrary text.
//

#import <XCTest/XCTest.h>
#import "BPBrewfile.h"

@interface BPBrewfileTests : XCTestCase
@end

@implementation BPBrewfileTests

- (BOOL)accepts:(NSString *)name
{
	return [BPBrewfile isBrewfileURL:[NSURL fileURLWithPath:[@"/tmp" stringByAppendingPathComponent:name]]];
}

#pragma mark - What counts

- (void)testDefaultFilenameKeepsTheCanonicalHomebrewName
{
	XCTAssertEqualObjects([BPBrewfile defaultFilename], @"Brewfile");
	XCTAssertTrue([self accepts:[BPBrewfile defaultFilename]]);
}

- (void)testTheCanonicalNameIsAccepted
{
	XCTAssertTrue([self accepts:@"Brewfile"]);
}

/// The filesystem is case-insensitive by default, so a file the user thinks is
/// a Brewfile can be spelled either way.
- (void)testTheNameIsMatchedCaseInsensitively
{
	XCTAssertTrue([self accepts:@"brewfile"]);
	XCTAssertTrue([self accepts:@"BREWFILE"]);
}

/// `brew bundle --file=` takes any path, and people really do keep
/// work.Brewfile next to personal.Brewfile.
- (void)testAQualifiedBrewfileIsAccepted
{
	XCTAssertTrue([self accepts:@"work.Brewfile"]);
	XCTAssertTrue([self accepts:@"personal.brewfile"]);
}

#pragma mark - What does not

/// The lock file sits right next to the Brewfile and is JSON, not a bundle
/// description. Feeding it to `brew bundle` is not something to offer.
- (void)testTheLockFileIsRejected
{
	XCTAssertFalse([self accepts:@"Brewfile.lock.json"]);
}

- (void)testAnUnrelatedNameIsRejected
{
	XCTAssertFalse([self accepts:@"README"]);
	XCTAssertFalse([self accepts:@"Brewfile.txt"]);
	XCTAssertFalse([self accepts:@"Podfile"]);
	XCTAssertFalse([self accepts:@"my-brewfile-notes.md"]);
}

- (void)testNonFileAndMissingURLsAreRejected
{
	XCTAssertFalse([BPBrewfile isBrewfileURL:nil]);
	XCTAssertFalse([BPBrewfile isBrewfileURL:[NSURL URLWithString:@"https://example.com/Brewfile"]]);
}

#pragma mark - Filtering a drop

/// A drop or an open can carry several files. Import takes one Brewfile, so
/// the non-Brewfiles are dropped rather than the whole gesture refused.
- (void)testFilteringKeepsOnlyBrewfilesInOrder
{
	NSArray<NSURL *> *urls = @[ [NSURL fileURLWithPath:@"/tmp/README"],
								[NSURL fileURLWithPath:@"/tmp/work.Brewfile"],
								[NSURL fileURLWithPath:@"/tmp/Brewfile.lock.json"],
								[NSURL fileURLWithPath:@"/tmp/Brewfile"] ];

	NSArray<NSURL *> *filtered = [BPBrewfile brewfileURLsFrom:urls];

	XCTAssertEqual(filtered.count, 2u);
	XCTAssertEqualObjects(filtered.firstObject.lastPathComponent, @"work.Brewfile");
	XCTAssertEqualObjects(filtered.lastObject.lastPathComponent, @"Brewfile");
}

- (void)testFilteringNothingYieldsNothingRatherThanNil
{
	XCTAssertEqualObjects([BPBrewfile brewfileURLsFrom:@[]], @[]);
	XCTAssertEqualObjects([BPBrewfile brewfileURLsFrom:nil], @[]);
}

@end
