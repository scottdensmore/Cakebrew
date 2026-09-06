//
//  BPTaskCancelTests.m
//  CakebrewTests
//
//  Once an operation started there was no way out: the operation sheet's only
//  button was a disabled OK, re-enabled after the task returned, and the sheet
//  is attached to the main window — so for the whole duration of a large cask
//  download or a source build the user could not dismiss it, use the app, or
//  abort a mistaken operation. BPTask had no cancel API at all.
//
//  Killing the NSTask alone is not enough: the task is a login shell running
//  brew, and brew spawns its own children (curl, git, compilers). Terminating
//  only the shell orphans them, so a "cancelled" download keeps running.
//

#import <XCTest/XCTest.h>
#import "BPTask.h"

@interface BPTaskCancelTests : XCTestCase
@end

@implementation BPTaskCancelTests

- (void)testCancelledProgressPreventsLaunchBeforeAsynchronousHandlerDelivery
{
 BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", @"echo DELAYED_HANDLER_LAUNCH"]];
 NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
 task.cancellationProgress = progress;
 // Deliberately no handler calls -cancel: the task must inspect the token.
 [progress cancel];
 XCTAssertFalse(task.wasCancelled);
 XCTAssertNotEqual([task execute], 0);
 XCTAssertTrue(task.wasCancelled);
 XCTAssertFalse([task.output containsString:@"DELAYED_HANDLER_LAUNCH"]);
}

- (void)testCancelledBeforeExecuteNeverLaunchesAndCannotReportSuccess
{
 BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", @"echo SHOULD_NOT_EXECUTE"]];
 [task cancel];
 XCTAssertNotEqual([task execute], 0);
 XCTAssertFalse([task.output containsString:@"SHOULD_NOT_EXECUTE"]);
}

/// Runs `task` off the main thread; returns the exit status via `status`.
- (BOOL)run:(BPTask *)task timeout:(NSTimeInterval)timeout status:(int *)status
{
	XCTestExpectation *finished = [self expectationWithDescription:@"finished"];
	__block int result = 0;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		result = [task execute];
		[finished fulfill];
	});
	XCTWaiterResult waited = [XCTWaiter waitForExpectations:@[finished] timeout:timeout];
	if (status) { *status = result; }
	return waited == XCTWaiterResultCompleted;
}

- (void)testCancellingEndsATaskThatWouldOtherwiseRunOn
{
	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", @"echo started; sleep 120"]];

	XCTestExpectation *started = [self expectationWithDescription:@"started"];
	__block BOOL signalled = NO;
	task.updateBlock = ^(NSString *chunk) {
		if (!signalled && [chunk containsString:@"started"]) { signalled = YES; [started fulfill]; }
	};

	XCTestExpectation *finished = [self expectationWithDescription:@"finished"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		[task execute];
		[finished fulfill];
	});

	XCTAssertEqual([XCTWaiter waitForExpectations:@[started] timeout:15.0], XCTWaiterResultCompleted);
	[task cancel];

	// Without cancel this would sit for two minutes.
	XCTAssertEqual([XCTWaiter waitForExpectations:@[finished] timeout:15.0], XCTWaiterResultCompleted,
				   @"cancel should end the run promptly");
}

- (void)testCancellingKillsTheChildrenBrewWouldHaveSpawned
{
	// The shell outlives nothing, but its children do unless they are killed
	// too — brew's downloads and builds are all children.
	NSString *marker = [NSString stringWithFormat:@"cakebrew-cancel-%@", [[NSUUID UUID] UUIDString]];
	NSString *script = [NSString stringWithFormat:@"sh -c 'exec -a %@ sleep 120' & echo started; wait", marker];

	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", script]];
	XCTestExpectation *started = [self expectationWithDescription:@"started"];
	__block BOOL signalled = NO;
	task.updateBlock = ^(NSString *chunk) {
		if (!signalled && [chunk containsString:@"started"]) { signalled = YES; [started fulfill]; }
	};

	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [task execute]; });
	XCTAssertEqual([XCTWaiter waitForExpectations:@[started] timeout:15.0], XCTWaiterResultCompleted);

	[task cancel];

	// Give the signals a moment, then confirm nothing of ours is left running.
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
	BOOL gone = NO;
	while (!gone && [deadline timeIntervalSinceNow] > 0)
	{
		gone = ![self anyProcessMatching:marker];
		if (!gone) { [NSThread sleepForTimeInterval:0.25]; }
	}

	if (!gone) { system([[NSString stringWithFormat:@"pkill -f %@", marker] UTF8String]); }
	XCTAssertTrue(gone, @"cancelling must not leave brew's children running");
}

- (BOOL)anyProcessMatching:(NSString *)marker
{
	NSTask *pgrep = [[NSTask alloc] init];
	pgrep.launchPath = @"/usr/bin/pgrep";
	pgrep.arguments = @[@"-f", marker];
	pgrep.standardOutput = [NSPipe pipe];
	pgrep.standardError = [NSPipe pipe];
	[pgrep launch];
	[pgrep waitUntilExit];
	return pgrep.terminationStatus == 0;
}

- (void)testCancellingBeforeLaunchIsHarmless
{
	// The user can hit Cancel between presenting the sheet and the process
	// actually starting.
	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", @"true"]];
	XCTAssertNoThrow([task cancel]);
}

- (void)testACancelledTaskReportsFailureRatherThanSuccess
{
	// operationStatus drives the "finished" vs "failed" wording, and a
	// cancelled run is not a success.
	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", @"echo started; sleep 120"]];
	XCTestExpectation *started = [self expectationWithDescription:@"started"];
	__block BOOL signalled = NO;
	task.updateBlock = ^(NSString *chunk) {
		if (!signalled && [chunk containsString:@"started"]) { signalled = YES; [started fulfill]; }
	};

	__block int status = 0;
	XCTestExpectation *finished = [self expectationWithDescription:@"finished"];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		status = [task execute];
		[finished fulfill];
	});

	XCTAssertEqual([XCTWaiter waitForExpectations:@[started] timeout:15.0], XCTWaiterResultCompleted);
	[task cancel];
	XCTAssertEqual([XCTWaiter waitForExpectations:@[finished] timeout:15.0], XCTWaiterResultCompleted);

	XCTAssertNotEqual(status, 0, @"a cancelled run must not report success");
	XCTAssertTrue(task.wasCancelled, @"the caller needs to tell cancellation from a brew failure");
}

@end
