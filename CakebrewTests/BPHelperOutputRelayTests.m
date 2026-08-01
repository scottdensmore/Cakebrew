//
//  BPHelperOutputRelayTests.m
//  CakebrewTests
//
//  The relay mirrors what BPTask does today: accumulate the whole output for
//  the caller while forwarding chunks live. Over XPC the forwarding side is a
//  remote proxy, so the sink is optional and must never be called blindly —
//  the same nil-callback class of bug that crashed pin/unpin (#42).
//

#import <XCTest/XCTest.h>
#import "BPHelperOutputRelay.h"

@interface BPHelperOutputRelayTests : XCTestCase
@end

@implementation BPHelperOutputRelayTests

static NSData *D(NSString *s) { return [s dataUsingEncoding:NSUTF8StringEncoding]; }

#pragma mark - accumulation

- (void)testAccumulatesChunksInOrder
{
	BPHelperOutputRelay *relay = [[BPHelperOutputRelay alloc] initWithSink:nil];
	[relay appendData:D(@"==> Downloading\n")];
	[relay appendData:D(@"==> Pouring\n")];

	XCTAssertEqualObjects(relay.accumulatedOutput, @"==> Downloading\n==> Pouring\n");
}

- (void)testAccumulatedOutputIsEmptyWhenNothingArrived
{
	BPHelperOutputRelay *relay = [[BPHelperOutputRelay alloc] initWithSink:nil];
	XCTAssertEqualObjects(relay.accumulatedOutput, @"");
}

#pragma mark - forwarding

- (void)testForwardsEachChunkToTheSink
{
	NSMutableArray<NSString *> *chunks = [NSMutableArray array];
	BPHelperOutputRelay *relay = [[BPHelperOutputRelay alloc] initWithSink:^(NSString *chunk) {
		[chunks addObject:chunk];
	}];

	[relay appendData:D(@"first")];
	[relay appendData:D(@"second")];

	XCTAssertEqualObjects(chunks, (@[ @"first", @"second" ]),
						  @"chunks stream as they arrive rather than only at the end");
}

- (void)testNilSinkIsSafe
{
	// A nil sink is legitimate (sync calls want only the final output).
	BPHelperOutputRelay *relay = [[BPHelperOutputRelay alloc] initWithSink:nil];
	XCTAssertNoThrow([relay appendData:D(@"no sink attached")]);
	XCTAssertEqualObjects(relay.accumulatedOutput, @"no sink attached",
						  @"accumulation still happens without a sink");
}

- (void)testEmptyDataIsNotForwarded
{
	__block NSUInteger calls = 0;
	BPHelperOutputRelay *relay = [[BPHelperOutputRelay alloc] initWithSink:^(NSString *chunk) { calls++; }];

	[relay appendData:[NSData data]];
	[relay appendData:nil];

	XCTAssertEqual(calls, 0u, @"empty reads must not generate XPC traffic");
	XCTAssertEqualObjects(relay.accumulatedOutput, @"");
}

#pragma mark - robustness

- (void)testSplitMultiByteCharacterDoesNotCorruptOutput
{
	// A pipe read can split a UTF-8 sequence; brew output contains ✔/✘/→.
	NSData *full = D(@"✔");
	BPHelperOutputRelay *relay = [[BPHelperOutputRelay alloc] initWithSink:nil];
	[relay appendData:[full subdataWithRange:NSMakeRange(0, 1)]];
	[relay appendData:[full subdataWithRange:NSMakeRange(1, full.length - 1)]];

	XCTAssertEqualObjects(relay.accumulatedOutput, @"✔",
						  @"a character split across reads must be reassembled");
}

- (void)testConcurrentAppendsDoNotLoseOutput
{
	// The pipe's readability handler fires on a background queue.
	BPHelperOutputRelay *relay = [[BPHelperOutputRelay alloc] initWithSink:nil];
	dispatch_apply(200, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(size_t i) {
		[relay appendData:D(@"x")];
	});

	XCTAssertEqual(relay.accumulatedOutput.length, 200u, @"no writes lost under concurrency");
}

@end
