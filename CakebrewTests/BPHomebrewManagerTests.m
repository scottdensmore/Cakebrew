//
//  BPHomebrewManagerTests.m
//  CakebrewTests
//
//  Tests for BPHomebrewManager's pure status logic: statusForFormula: derives a
//  formula's state from the installed/outdated lists, matching by installedName
//  (so tap-qualified and short names compare equal).
//

#import <XCTest/XCTest.h>
#import "BPHomebrewManager.h"
#import "BPFormula.h"

/// The cask list parsers set this flag in production; fixtures set it directly.
@interface BPMockCaskFlag : NSObject
+ (void)markAsCasks:(NSArray<BPFormula *> *)formulae;
@end

@implementation BPMockCaskFlag
+ (void)markAsCasks:(NSArray<BPFormula *> *)formulae
{
	for (BPFormula *formula in formulae) { formula.cask = YES; }
}
@end

@interface BPHomebrewManagerTests : XCTestCase <BPHomebrewManagerDelegate>
@property (strong) BPHomebrewManager *manager;
@property (nonatomic, copy) void (^searchCompletion)(void);
@end

@implementation BPHomebrewManagerTests

- (void)setUp
{
	[super setUp];
	// BPHomebrewManager is a singleton (alloc/init are unavailable). Each test
	// sets the lists it needs, and setUp/tearDown reset them so there is no
	// state bleed between tests.
	self.manager = [BPHomebrewManager sharedManager];
	self.manager.delegate = self;
	self.manager.installedFormulae = @[];
	self.manager.outdatedFormulae = @[];
	self.manager.allFormulae = @[];
	self.manager.searchFormulae = @[];
	self.manager.pinnedFormulae = @[];
	self.manager.installedCasks = @[];
	self.manager.outdatedCasks = @[];
}

- (void)tearDown
{
	self.manager.installedFormulae = @[];
	self.manager.outdatedFormulae = @[];
	self.manager.allFormulae = @[];
	self.manager.searchFormulae = @[];
	self.manager.pinnedFormulae = @[];
	self.manager.installedCasks = @[];
	self.manager.outdatedCasks = @[];
	self.manager = nil;
	[super tearDown];
}

/// Runs a search and waits for it to publish. The scan moved off the main
/// thread (8.5k names per keystroke was blocking it), so results arrive on a
/// later turn of the run loop rather than before the call returns.
- (void)search:(NSString *)query
{
	[self.manager updateSearchWithName:query];

	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5.0];
	__block BOOL published = NO;
	// The delegate callback is the completion signal; polling searchFormulae
	// cannot distinguish "not yet" from "no matches".
	self.searchCompletion = ^{ published = YES; };
	while (!published && [deadline timeIntervalSinceNow] > 0)
	{
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
	}
	self.searchCompletion = nil;
	XCTAssertTrue(published, @"the search for '%@' never published", query);
}

- (void)testUpdateSearchFiltersAllFormulaeByName
{
	BPFormula *wget = [BPFormula formulaWithName:@"wget"];
	BPFormula *git = [BPFormula formulaWithName:@"git"];
	BPFormula *wgetpaste = [BPFormula formulaWithName:@"wgetpaste"];
	self.manager.allFormulae = @[ wget, git, wgetpaste ];

	[self search:@"wget"];

	XCTAssertEqual(self.manager.searchFormulae.count, 2u, @"wget and wgetpaste contain 'wget'");
	XCTAssertTrue([self.manager.searchFormulae containsObject:wget]);
	XCTAssertTrue([self.manager.searchFormulae containsObject:wgetpaste]);
	XCTAssertFalse([self.manager.searchFormulae containsObject:git]);
}

- (void)testUpdateSearchIsCaseInsensitive
{
	BPFormula *node = [BPFormula formulaWithName:@"node"];
	self.manager.allFormulae = @[ node ];

	[self search:@"NODE"];

	XCTAssertEqualObjects(self.manager.searchFormulae, @[ node ]);
}

- (void)testUpdateSearchWithNoMatchesIsEmpty
{
	self.manager.allFormulae = @[ [BPFormula formulaWithName:@"wget"] ];

	[self search:@"zzznope"];

	XCTAssertEqual(self.manager.searchFormulae.count, 0u);
}

- (void)testStatusIsNotInstalledWhenAbsent
{
	self.manager.installedFormulae = @[[BPFormula formulaWithName:@"git"]];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"wget"]], kBPFormulaNotInstalled);
}

- (void)testStatusIsInstalledWhenPresentAndNotOutdated
{
	self.manager.installedFormulae = @[[BPFormula formulaWithName:@"git"]];
	self.manager.outdatedFormulae = @[];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"git"]], kBPFormulaInstalled);
}

- (void)testStatusIsOutdatedWhenPresentInBoth
{
	self.manager.installedFormulae = @[[BPFormula formulaWithName:@"git"]];
	self.manager.outdatedFormulae = @[[BPFormula formulaWithName:@"git"]];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"git"]], kBPFormulaOutdated);
}

- (void)testStatusMatchesByShortNameAcrossTaps
{
	// Installed under the short name; a tap-qualified query still matches via installedName.
	self.manager.installedFormulae = @[[BPFormula formulaWithName:@"foo"]];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"homebrew/core/foo"]], kBPFormulaInstalled);
}

- (void)testStatusIsNotInstalledWhenOnlyInOutdatedList
{
	// statusForFormula gates on the installed list first, so a formula that is
	// only in the outdated list (but not installed) is reported as not installed.
	self.manager.installedFormulae = @[];
	self.manager.outdatedFormulae = @[[BPFormula formulaWithName:@"git"]];
	XCTAssertEqual([self.manager statusForFormula:[BPFormula formulaWithName:@"git"]], kBPFormulaNotInstalled);
}

#pragma mark - cask status (statusForFormula: reads the cask lists)

- (BPFormula *)caskWithName:(NSString *)name
{
	BPFormula *cask = [BPFormula formulaWithName:name];
	cask.cask = YES;
	return cask;
}

- (void)testStatusForCaskInstalledWhenInInstalledCasks
{
	self.manager.installedCasks = @[ [self caskWithName:@"firefox"] ];
	XCTAssertEqual([self.manager statusForFormula:[self caskWithName:@"firefox"]], kBPFormulaInstalled);
}

- (void)testStatusForCaskOutdatedWhenInBothCaskLists
{
	self.manager.installedCasks = @[ [self caskWithName:@"firefox"] ];
	self.manager.outdatedCasks = @[ [self caskWithName:@"firefox"] ];
	XCTAssertEqual([self.manager statusForFormula:[self caskWithName:@"firefox"]], kBPFormulaOutdated);
}

- (void)testStatusForCaskNotInstalledWhenAbsentFromCaskLists
{
	self.manager.installedCasks = @[ [self caskWithName:@"chrome"] ];
	XCTAssertEqual([self.manager statusForFormula:[self caskWithName:@"firefox"]], kBPFormulaNotInstalled);
}

- (void)testStatusForCaskIgnoresFormulaListsOnNameCollision
{
	// A cask must not read the formula lists even when a formula shares its name.
	self.manager.installedFormulae = @[ [BPFormula formulaWithName:@"firefox"] ];
	XCTAssertEqual([self.manager statusForFormula:[self caskWithName:@"firefox"]], kBPFormulaNotInstalled);
}

#pragma mark - pinned state (isFormulaPinned:)

- (void)testIsFormulaPinnedReturnsYesForPinnedFormula
{
	BPFormula *git = [BPFormula formulaWithName:@"git"];
	self.manager.pinnedFormulae = @[ git ];

	XCTAssertTrue([self.manager isFormulaPinned:git]);
}

- (void)testIsFormulaPinnedReturnsNoForUnpinnedFormula
{
	self.manager.pinnedFormulae = @[ [BPFormula formulaWithName:@"git"] ];

	XCTAssertFalse([self.manager isFormulaPinned:[BPFormula formulaWithName:@"wget"]]);
}

- (void)testIsFormulaPinnedIsFalseWhenNothingPinned
{
	self.manager.pinnedFormulae = @[];
	XCTAssertFalse([self.manager isFormulaPinned:[BPFormula formulaWithName:@"git"]]);
}

- (void)testIsFormulaPinnedMatchesByShortNameAcrossTaps
{
	// `brew list --pinned` may emit tap-qualified names; matching uses installedName.
	self.manager.pinnedFormulae = @[ [BPFormula formulaWithName:@"homebrew/core/git"] ];
	XCTAssertTrue([self.manager isFormulaPinned:[BPFormula formulaWithName:@"git"]]);
}


#pragma mark - search covers casks

- (NSArray<NSString *> *)namesOf:(NSArray<BPFormula *> *)formulae
{
	return [formulae valueForKeyPath:@"@unionOfObjects.name"];
}

- (void)testSearchMatchesCasksAsWellAsFormulae
{
	// Typing "chrome" returned nothing even though the cask browse lists show
	// it: the matcher only ever walked allFormulae.
	NSArray *formulae = @[ [BPFormula formulaWithName:@"wget"] ];
	NSArray *casks = @[ [BPFormula formulaWithName:@"mockchrome"] ];
	[BPMockCaskFlag markAsCasks:casks];

	NSArray *matches = [BPHomebrewManager formulae:formulae casks:casks matchingQuery:@"chrome"];

	XCTAssertEqualObjects([self namesOf:matches], (@[ @"mockchrome" ]));
}

- (void)testAMatchedCaskStaysACask
{
	// statusForFormula:, the detail pane and operation dispatch all branch on
	// this flag, so a search hit that loses it would be treated as a formula.
	NSArray *casks = @[ [BPFormula formulaWithName:@"mockchrome"] ];
	[BPMockCaskFlag markAsCasks:casks];

	NSArray *matches = [BPHomebrewManager formulae:@[] casks:casks matchingQuery:@"chrome"];

	XCTAssertEqual(matches.count, 1u);
	XCTAssertTrue([(BPFormula *)matches.firstObject cask], @"a matched cask must still dispatch as --cask");
}

- (void)testSearchIsCaseInsensitiveAcrossBothNamespaces
{
	NSArray *formulae = @[ [BPFormula formulaWithName:@"WGet"] ];
	NSArray *casks = @[ [BPFormula formulaWithName:@"MockChrome"] ];
	[BPMockCaskFlag markAsCasks:casks];

	XCTAssertEqual([BPHomebrewManager formulae:formulae casks:casks matchingQuery:@"wget"].count, 1u);
	XCTAssertEqual([BPHomebrewManager formulae:formulae casks:casks matchingQuery:@"chrome"].count, 1u);
}

- (void)testFormulaeComeBeforeCasksSoTheNamespacesAreNotInterleaved
{
	NSArray *formulae = @[ [BPFormula formulaWithName:@"zzz-formula"] ];
	NSArray *casks = @[ [BPFormula formulaWithName:@"aaa-cask"] ];
	[BPMockCaskFlag markAsCasks:casks];

	NSArray *matches = [BPHomebrewManager formulae:formulae casks:casks matchingQuery:@"a"];
	XCTAssertEqualObjects([self namesOf:matches], (@[ @"zzz-formula", @"aaa-cask" ]));
}

- (void)testAnEmptyQueryMatchesNothing
{
	// Clearing the field ends the search; it should not dump the whole catalog.
	NSArray *formulae = @[ [BPFormula formulaWithName:@"wget"] ];
	XCTAssertEqual([BPHomebrewManager formulae:formulae casks:@[] matchingQuery:@""].count, 0u);
	XCTAssertEqual([BPHomebrewManager formulae:formulae casks:@[] matchingQuery:nil].count, 0u);
}

#pragma mark - late results

- (void)testResultsForASupersededQueryAreDiscarded
{
	// Scanning 8.5k names is slow enough that a slower earlier query can land
	// after a faster later one and overwrite it.
	XCTAssertTrue([BPHomebrewManager shouldPublishResultsForQuery:@"chrome" currentQuery:@"chrome"]);
	XCTAssertFalse([BPHomebrewManager shouldPublishResultsForQuery:@"chr" currentQuery:@"chrome"],
				   @"a result for an earlier keystroke must not replace the current one");
	XCTAssertFalse([BPHomebrewManager shouldPublishResultsForQuery:@"chrome" currentQuery:nil],
				   @"the search was cancelled while this was running");
}


#pragma mark - BPHomebrewManagerDelegate

- (void)homebrewManager:(BPHomebrewManager *)manager didUpdateSearchResults:(NSArray *)searchResults
{
	if (self.searchCompletion) { self.searchCompletion(); }
}

- (void)homebrewManagerFinishedUpdating:(BPHomebrewManager *)manager {}
- (void)homebrewManager:(BPHomebrewManager *)manager shouldDisplayNoBrewMessage:(BOOL)yesOrNo {}


#pragma mark - reload coalescing

- (void)testASecondReloadRequestDoesNotStartASecondPipeline
{
	// Four callers can fire a reload — launch, the background timer,
	// post-operation, and unlock-after-no-brew — and the timer only checks
	// whether a brew *operation* is running, not whether a reload already is.
	XCTAssertTrue([BPHomebrewManager shouldStartReloadWhenInFlight:NO]);
	XCTAssertFalse([BPHomebrewManager shouldStartReloadWhenInFlight:YES],
				   @"a concurrent request should coalesce, not start a second pipeline");
}

- (void)testOnlyTheNewestPipelineMayPublish
{
	// Whichever pipeline finished last used to win the property assignments,
	// so a slower older snapshot could clobber a newer one.
	XCTAssertTrue([BPHomebrewManager shouldPublishReloadGeneration:4 current:4]);
	XCTAssertFalse([BPHomebrewManager shouldPublishReloadGeneration:3 current:4],
				   @"a superseded snapshot must be discarded, not published");
}

@end
