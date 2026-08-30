//
//  BPLoadingStatusTests.m
//  CakebrewTests
//
//  The loading overlay was an indeterminate spinner with a hardcoded "Loading"
//  label. A cold cask catalog takes 80+ seconds, and for all of that the app
//  looked identical to one that had hung.
//
//  Saying which step is running is what distinguishes the two, so the mapping
//  from list to status text is what this covers — including that the slow step
//  says it is slow, which is the whole reason anyone waits rather than force
//  quitting.
//

#import <XCTest/XCTest.h>
#import "BPLoadingStatus.h"
#import "BPHomebrewInterface.h"

@interface BPLoadingStatusTests : XCTestCase
@end

@implementation BPLoadingStatusTests

- (NSArray<NSNumber *> *)reloadedModes
{
	return @[ @(kBPListInstalled), @(kBPListOutdated), @(kBPListAll), @(kBPListLeaves),
			  @(kBPListPinned), @(kBPListRepositories), @(kBPListInstalledCasks),
			  @(kBPListOutdatedCasks), @(kBPListAllCasks) ];
}

#pragma mark - A step for every list

/// A missing case would leave the previous step's text on screen, which is
/// exactly the bug that made this worth having.
- (void)testEveryReloadedListHasItsOwnStatusKey
{
	NSMutableSet<NSString *> *keys = [NSMutableSet set];

	for (NSNumber *mode in [self reloadedModes])
	{
		NSString *key = [BPLoadingStatus localizationKeyForListMode:(BPListMode)mode.integerValue];

		XCTAssertNotNil(key, @"mode %@ has no status", mode);
		XCTAssertFalse([keys containsObject:key], @"mode %@ reuses the status of an earlier list", mode);
		[keys addObject:key];
	}
}

/// Search is not part of a reload and has no step of its own.
- (void)testSearchHasNoStatus
{
	XCTAssertNil([BPLoadingStatus localizationKeyForListMode:kBPListSearch]);
}

#pragma mark - The keys really ship

/// NSLocalizedString returns the key when the string is missing, so an
/// unshipped key would be displayed verbatim. The test bundle carries no
/// Localizable.strings, so this checks the source file — BPLocalizationParity
/// covers the other five locales.
- (void)testEveryStatusKeyIsInTheStringsFile
{
	NSString *repoRoot = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSString *path = [repoRoot stringByAppendingPathComponent:@"Cakebrew/en.lproj/Localizable.strings"];
	NSString *english = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];

	XCTAssertTrue(english.length > 0, @"could not read en.lproj at %@", path);

	for (NSNumber *mode in [self reloadedModes])
	{
		NSString *key = [BPLoadingStatus localizationKeyForListMode:(BPListMode)mode.integerValue];
		// Hoisted: a comma inside [ ] does not protect it from the XCTAssert
		// macro's argument splitting — only parentheses do.
		NSString *quoted = [NSString stringWithFormat:@"\"%@\" =", key];
		XCTAssertTrue([english containsString:quoted], @"%@ is not in en.lproj", key);
	}

	XCTAssertTrue([english containsString:@"\"Loading_Status_Default\" ="]);
	XCTAssertTrue([english containsString:@"\"Loading_Cancel\" ="]);
}

#pragma mark - Which steps are worth warning about

/// The two full catalogs are the slow ones — `brew casks` alone can take 80
/// seconds cold. Nothing else in a reload runs long enough to need an excuse,
/// and marking a fast step slow would train people to ignore the warning.
- (void)testOnlyTheCatalogFetchesAreMarkedSlow
{
	XCTAssertTrue([BPLoadingStatus isSlowListMode:kBPListAll]);
	XCTAssertTrue([BPLoadingStatus isSlowListMode:kBPListAllCasks]);

	XCTAssertFalse([BPLoadingStatus isSlowListMode:kBPListInstalled]);
	XCTAssertFalse([BPLoadingStatus isSlowListMode:kBPListOutdated]);
	XCTAssertFalse([BPLoadingStatus isSlowListMode:kBPListPinned]);
	XCTAssertFalse([BPLoadingStatus isSlowListMode:kBPListSearch]);
}

@end
