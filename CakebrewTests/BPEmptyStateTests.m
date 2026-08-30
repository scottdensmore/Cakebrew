//
//  BPEmptyStateTests.m
//  CakebrewTests
//
//  The app had no empty-state affordance anywhere: both row-count methods
//  returned the array count with no zero-row branch. So a search that matched
//  nothing, Outdated when everything is up to date (the happy path), Pinned
//  before anything is pinned, and Services with none installed all produced the
//  same thing — column headers over blank space, with no way to tell "nothing
//  matched" from "still loading" from "something broke".
//

#import <XCTest/XCTest.h>
#import "BPEmptyState.h"
#import "BPSideBarController.h"

@interface BPEmptyStateTests : XCTestCase
@end

@implementation BPEmptyStateTests

- (void)testTheHappyPathHasItsOwnWording
{
	// Outdated being empty is good news, not an error, and should read that way.
	BPEmptyState *state = [BPEmptyState stateForSidebarRow:FormulaeSideBarItemOutdated searching:NO];

	XCTAssertNotNil(state);
	XCTAssertEqualObjects(state.titleKey, @"Empty_Outdated_Title");
	XCTAssertEqualObjects(state.messageKey, @"Empty_Outdated_Message");
	XCTAssertGreaterThan(state.symbolName.length, 0u);
}

- (void)testSearchingTakesPrecedenceOverWhicheverRowIsSelected
{
	// A no-result search should explain the search, not the underlying list.
	BPEmptyState *state = [BPEmptyState stateForSidebarRow:FormulaeSideBarItemAll searching:YES];

	XCTAssertEqualObjects(state.titleKey, @"Empty_Search_Title");
}

- (void)testEachListHasItsOwnState
{
	NSDictionary<NSNumber *, NSString *> *expected = @{
		@(FormulaeSideBarItemOutdated):      @"Empty_Outdated_Title",
		@(FormulaeSideBarItemPinned):        @"Empty_Pinned_Title",
		@(FormulaeSideBarItemServices):      @"Empty_Services_Title",
		@(FormulaeSideBarItemInstalledCasks):@"Empty_Casks_Title",
		@(FormulaeSideBarItemOutdatedCasks): @"Empty_OutdatedCasks_Title",
		@(FormulaeSideBarItemLeaves):        @"Empty_Leaves_Title",
	};

	[expected enumerateKeysAndObjectsUsingBlock:^(NSNumber *row, NSString *key, BOOL *stop) {
		BPEmptyState *state = [BPEmptyState stateForSidebarRow:row.integerValue searching:NO];
		XCTAssertEqualObjects(state.titleKey, key, @"row %@", row);
	}];
}

- (void)testAListWithNoSpecificWordingStillGetsAState
{
	// Better a generic "Nothing here" than headers over blank space.
	BPEmptyState *state = [BPEmptyState stateForSidebarRow:FormulaeSideBarItemInstalled searching:NO];

	XCTAssertNotNil(state);
	XCTAssertGreaterThan(state.titleKey.length, 0u);
}

- (void)testNothingIsShownWhileTheListIsStillLoading
{
	// The whole point is distinguishing empty from loading; showing "No
	// Results" during the first reload would be a lie.
	XCTAssertFalse([BPEmptyState shouldShowForRowCount:0 loading:YES]);
	XCTAssertTrue([BPEmptyState shouldShowForRowCount:0 loading:NO]);
}

- (void)testNothingIsShownWhenThereAreRows
{
	XCTAssertFalse([BPEmptyState shouldShowForRowCount:3 loading:NO]);
	XCTAssertFalse([BPEmptyState shouldShowForRowCount:3 loading:YES]);
}

@end
