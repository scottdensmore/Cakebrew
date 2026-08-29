//
//  BPTaskStreamingTests.m
//  CakebrewTests
//
//  BPTask answered NSFileHandleDataAvailableNotification with
//  -readDataToEndOfFile, which blocks until the child closes the pipe. Nothing
//  streamed (the operation sheet stayed blank for the whole run), and because
//  the reading thread was parked in one pipe, the other was never drained —
//  brew filling the unread pipe's 64 KB buffer would block on write and never
//  exit, wedging the app.
//
//  These tests drive a real /bin/sh so they exercise the pipe plumbing rather
//  than a stub. Each one is bounded: on the pre-fix code they time out rather
//  than hang the suite.
//

#import <XCTest/XCTest.h>
#import "BPTask.h"

@interface BPTaskStreamingTests : XCTestCase
@end

@implementation BPTaskStreamingTests

#pragma mark - helpers

/// Runs `task` off the main thread and waits up to `timeout` for it to finish.
/// Returns NO if it did not, after terminating it so the suite can continue.
- (BOOL)runTask:(BPTask *)task timeout:(NSTimeInterval)timeout status:(int *)status
{
	XCTestExpectation *finished = [self expectationWithDescription:@"task finished"];
	__block int result = -1;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		result = [task execute];
		[finished fulfill];
	});

	XCTWaiterResult waited = [XCTWaiter waitForExpectations:@[finished] timeout:timeout];
	if (waited != XCTWaiterResultCompleted)
	{
		[task cleanup];
		return NO;
	}
	if (status != NULL)
	{
		*status = result;
	}
	return YES;
}

- (NSUInteger)countOf:(NSString *)needle in:(NSString *)haystack
{
	if (haystack.length == 0)
	{
		return 0;
	}
	NSUInteger count = 0;
	NSRange search = NSMakeRange(0, haystack.length);
	while (search.length > 0)
	{
		NSRange found = [haystack rangeOfString:needle options:0 range:search];
		if (found.location == NSNotFound)
		{
			break;
		}
		count++;
		NSUInteger next = NSMaxRange(found);
		search = NSMakeRange(next, haystack.length - next);
	}
	return count;
}

#pragma mark - streaming

- (void)testChunksAreDeliveredWhileTheProcessIsStillRunning
{
	// The script blocks until the test creates the gate file, and the test only
	// creates it from inside the update block. So the process can only exit if
	// output was delivered mid-run — the whole point of streaming.
	NSString *gate = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
	NSString *script = [NSString stringWithFormat:
						@"echo ready; while [ ! -f '%@' ]; do sleep 0.05; done; echo finished", gate];

	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", script]];
	__block BOOL opened = NO;
	task.updateBlock = ^(NSString *chunk) {
		if (!opened && [chunk containsString:@"ready"])
		{
			opened = YES;
			[[NSFileManager defaultManager] createFileAtPath:gate contents:[NSData data] attributes:nil];
		}
	};

	int status = -1;
	BOOL finished = [self runTask:task timeout:15.0 status:&status];
	[[NSFileManager defaultManager] removeItemAtPath:gate error:NULL];

	XCTAssertTrue(finished, @"the process never exited: output was not streamed while it ran");
	XCTAssertTrue(opened, @"the update block never saw the first line");
	XCTAssertEqual(status, 0);
	XCTAssertTrue([task.output containsString:@"finished"], @"the tail after the last chunk was lost");
}

- (void)testBothPipesDrainConcurrentlyBeyondThePipeBuffer
{
	// ~140 KB down each pipe, well past the 64 KB buffer. If only one pipe is
	// being read, the child blocks writing to the other and never exits.
	NSString *script =
		@"i=0; while [ $i -lt 4000 ]; do "
		@"echo 'out-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'; "
		@"echo 'err-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb' >&2; "
		@"i=$((i+1)); done";

	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", script]];
	task.updateBlock = ^(NSString *chunk) { /* streaming enabled */ };

	int status = -1;
	XCTAssertTrue([self runTask:task timeout:30.0 status:&status],
				  @"deadlocked: one pipe filled while the other was being read");
	XCTAssertEqual(status, 0);
	XCTAssertEqual([self countOf:@"out-" in:task.output], 4000u, @"stdout lost data");
	XCTAssertEqual([self countOf:@"err-" in:task.error], 4000u, @"stderr lost data");
}

- (void)testLargeOutputSurvivesWithoutAnUpdateBlock
{
	// The synchronous path (no update block) read stdout to end, then stderr —
	// same deadlock, and it is the path every list call takes.
	NSString *script =
		@"i=0; while [ $i -lt 4000 ]; do "
		@"echo 'out-cccccccccccccccccccccccccccccccccccccc'; "
		@"echo 'err-dddddddddddddddddddddddddddddddddddddd' >&2; "
		@"i=$((i+1)); done";

	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", script]];

	int status = -1;
	XCTAssertTrue([self runTask:task timeout:30.0 status:&status], @"deadlocked with no update block");
	XCTAssertEqual(status, 0);
	XCTAssertEqual([self countOf:@"out-" in:task.output], 4000u);
	XCTAssertEqual([self countOf:@"err-" in:task.error], 4000u);
}

#pragma mark - decoding

- (void)testMultiByteCharactersSplitAcrossReadsSurvive
{
	// brew prints ✔ / ✘ / → constantly. Past 64 KB the reads certainly split a
	// multi-byte sequence; -initWithData:encoding: returns nil on a partial
	// sequence, so an unbuffered decoder silently drops the whole chunk.
	NSString *script =
		@"i=0; while [ $i -lt 3000 ]; do printf '\\342\\234\\224\\342\\234\\230\\342\\206\\222 streaming check\\n'; i=$((i+1)); done";

	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", script]];
	__block NSMutableString *streamed = [NSMutableString string];
	task.updateBlock = ^(NSString *chunk) {
		@synchronized (streamed) { [streamed appendString:chunk ?: @""]; }
	};

	int status = -1;
	XCTAssertTrue([self runTask:task timeout:30.0 status:&status]);
	XCTAssertEqual(status, 0);

	XCTAssertEqual([self countOf:@"✔" in:task.output], 3000u, @"accumulated output dropped split sequences");
	XCTAssertEqual([self countOf:@"→" in:task.output], 3000u);
	@synchronized (streamed) {
		XCTAssertEqual([self countOf:@"✔" in:streamed], 3000u, @"streamed chunks dropped split sequences");
	}
}

#pragma mark - lifecycle

- (void)testNonZeroExitStatusIsReported
{
	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", @"echo nope >&2; exit 3"]];
	int status = -1;
	XCTAssertTrue([self runTask:task timeout:10.0 status:&status]);
	XCTAssertEqual(status, 3);
	XCTAssertTrue([task.error containsString:@"nope"]);
}

- (void)testStdinIsClosedSoChildrenDoNotBlockWaitingForInput
{
	// Nothing ever wrote to the task's stdin, but it was left attached to the
	// app's. A child that reads stdin would hang forever; it must see EOF.
	BPTask *task = [[BPTask alloc] initWithPath:@"/bin/sh" arguments:@[@"-c", @"cat; echo done"]];
	int status = -1;
	XCTAssertTrue([self runTask:task timeout:10.0 status:&status],
				  @"the child blocked reading stdin");
	XCTAssertEqual(status, 0);
	XCTAssertTrue([task.output containsString:@"done"]);
}

@end
