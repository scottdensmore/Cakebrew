//
//  BPBackgroundTaskGuardTests.m
//  CakebrewTests
//
//  -checkForBackgroundTask returned void, so its `return` only exited the
//  guard itself. Every caller invoked it as a bare statement in the shape of a
//  guard and then carried on regardless: the user saw the "a background task is
//  running" warning, dismissed it, was handed the operation's own confirmation
//  sheet, and confirming started a second brew run that Homebrew's own lock
//  then rejected with a raw error in the log.
//
//  The decision is now a pure predicate on BPAppDelegate — which owns both the
//  flag and the warning — following +shouldNotifyForCount:previousCount: in
//  BPBackgroundUpdater, so it can be tested without a window.
//

#import <XCTest/XCTest.h>
#import "BPAppDelegate.h"

@interface BPBackgroundTaskGuardTests : XCTestCase
@end

@implementation BPBackgroundTaskGuardTests

- (void)testAnOperationIsBlockedWhileABackgroundTaskRuns
{
	XCTAssertTrue([BPAppDelegate shouldBlockOperationWhileRunningBackgroundTask:YES],
				  @"starting a second brew run is what Homebrew's lock rejects");
}

- (void)testAnOperationProceedsWhenNothingIsRunning
{
	XCTAssertFalse([BPAppDelegate shouldBlockOperationWhileRunningBackgroundTask:NO]);
}

@end
