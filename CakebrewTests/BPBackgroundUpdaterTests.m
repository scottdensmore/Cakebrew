//
//  BPBackgroundUpdaterTests.m
//  CakebrewTests
//
//  Tests for the background updater's pure decision logic: what the dock
//  badge shows and when a notification is warranted.
//

#import <XCTest/XCTest.h>
#import "BPBackgroundUpdater.h"

@interface BPBackgroundUpdaterTests : XCTestCase
@end

@implementation BPBackgroundUpdaterTests

#pragma mark - badge label

- (void)testBadgeLabelIsNilWhenNothingOutdated
{
	XCTAssertNil([BPBackgroundUpdater badgeLabelForOutdatedCount:0],
				 @"no badge when everything is up to date");
}

- (void)testBadgeLabelShowsTheCount
{
	XCTAssertEqualObjects([BPBackgroundUpdater badgeLabelForOutdatedCount:1], @"1");
	XCTAssertEqualObjects([BPBackgroundUpdater badgeLabelForOutdatedCount:42], @"42");
}

#pragma mark - notification decision

- (void)testNotifiesWhenOutdatedCountRises
{
	XCTAssertTrue([BPBackgroundUpdater shouldNotifyForCount:3 previousCount:0]);
	XCTAssertTrue([BPBackgroundUpdater shouldNotifyForCount:5 previousCount:3]);
}

- (void)testDoesNotNotifyWhenNothingIsOutdated
{
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:0 previousCount:0]);
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:0 previousCount:4],
				   @"upgrading everything should not notify");
}

- (void)testDoesNotNotifyWhenCountIsUnchangedOrFalls
{
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:3 previousCount:3],
				   @"repeat checks with the same result stay quiet");
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:2 previousCount:3],
				   @"partially upgrading should not notify");
}


#pragma mark - the first observation is a baseline, not news

- (void)testTheFirstObservationSeedsTheBaselineAndDoesNotNotify
{
	// lastKnownOutdatedCount started at 0 in memory, and observers registered
	// before the first reload — so the first callback compared the real count
	// against 0 and banner-ed on every launch for news the user already had.
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:7 previousCount:0 hasBaseline:NO],
				   @"the first observation of a launch is what is already on disk, not an increase");
}

- (void)testAnIncreaseAfterTheBaselineNotifies
{
	XCTAssertTrue([BPBackgroundUpdater shouldNotifyForCount:8 previousCount:7 hasBaseline:YES]);
}

- (void)testNoIncreaseAfterTheBaselineDoesNotNotify
{
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:7 previousCount:7 hasBaseline:YES]);
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:3 previousCount:7 hasBaseline:YES]);
}

- (void)testAZeroCountNeverNotifiesEvenSeeded
{
	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:0 previousCount:0 hasBaseline:YES]);
}

- (void)testTheBaselineSurvivesRelaunch
{
	// Persisted, so quitting and reopening with the same outdated set is not
	// treated as news either.
	[BPBackgroundUpdater setPersistedOutdatedCount:5];
	XCTAssertEqual([BPBackgroundUpdater persistedOutdatedCount], 5u);
	XCTAssertTrue([BPBackgroundUpdater hasPersistedOutdatedCount]);

	XCTAssertFalse([BPBackgroundUpdater shouldNotifyForCount:5
											   previousCount:[BPBackgroundUpdater persistedOutdatedCount]
												 hasBaseline:[BPBackgroundUpdater hasPersistedOutdatedCount]]);
}

- (void)testClearingTheBaselineRestoresTheUnseededState
{
	[BPBackgroundUpdater setPersistedOutdatedCount:5];
	[BPBackgroundUpdater clearPersistedOutdatedCount];
	XCTAssertFalse([BPBackgroundUpdater hasPersistedOutdatedCount]);
}

@end
