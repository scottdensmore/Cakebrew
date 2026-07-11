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

@end
