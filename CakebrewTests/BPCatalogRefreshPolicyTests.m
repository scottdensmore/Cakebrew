//
//  BPCatalogRefreshPolicyTests.m
//  CakebrewTests
//
//  Every mutating operation used to end in a reload that forced
//  `reloadFromInterfaceRebuildingCache:YES`, which refetches `brew formulae`
//  and `brew casks` — 80+ seconds cold. Pinning a formula cannot change which
//  formulae exist, so paying that cost for a pin (or an unpin, or Doctor) was
//  pure waste, and it discarded the user's selection with no progress shown.
//
//  The policy now lives in one place: only commands that change which packages
//  *exist* justify refetching the catalogs. Which ones those are is exactly
//  what these tests pin.
//

#import <XCTest/XCTest.h>
#import "BPHomebrewInterface.h"

@interface BPCatalogRefreshPolicyTests : XCTestCase
@end

@implementation BPCatalogRefreshPolicyTests

#pragma mark - commands that change what exists

- (void)testUpdateRefetchesTheCatalogs
{
	// `brew update` is the whole point of the catalogs being refreshable.
	XCTAssertTrue([BPHomebrewInterface brewCommandChangesCatalogMembership:@"update"]);
}

- (void)testTappingAndUntappingRefetchTheCatalogs
{
	// A tap adds (or removes) formulae from what brew can see.
	XCTAssertTrue([BPHomebrewInterface brewCommandChangesCatalogMembership:@"tap"]);
	XCTAssertTrue([BPHomebrewInterface brewCommandChangesCatalogMembership:@"untap"]);
}

- (void)testBundleImportRefetchesTheCatalogs
{
	// A Brewfile can tap repositories as part of the import.
	XCTAssertTrue([BPHomebrewInterface brewCommandChangesCatalogMembership:@"bundle"]);
}

#pragma mark - commands that only change what is installed

- (void)testPinningAndUnpinningDoNotRefetchTheCatalogs
{
	// The regression this issue is about: pinning cost a full catalog rebuild.
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"pin"]);
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"unpin"]);
}

- (void)testDoctorDoesNotRefetchTheCatalogs
{
	// `brew doctor` changes nothing at all.
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"doctor"]);
}

- (void)testInstallUninstallAndUpgradeDoNotRefetchTheCatalogs
{
	// These change which packages are installed, not which ones exist.
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"install"]);
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"uninstall"]);
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"upgrade"]);
}

- (void)testCleanupAndExportDoNotRefetchTheCatalogs
{
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"cleanup"]);
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"export"]);
}

#pragma mark - robustness

- (void)testUnknownAndEmptyCommandsAreConservativelyTreatedAsCheap
{
	// A new operation that forgets to opt in gets the fast path rather than
	// silently reintroducing an 80-second stall.
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@"services"]);
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:@""]);
	XCTAssertFalse([BPHomebrewInterface brewCommandChangesCatalogMembership:nil]);
}

- (void)testMatchingIsCaseInsensitive
{
	XCTAssertTrue([BPHomebrewInterface brewCommandChangesCatalogMembership:@"UPDATE"]);
	XCTAssertTrue([BPHomebrewInterface brewCommandChangesCatalogMembership:@"Tap"]);
}

@end
