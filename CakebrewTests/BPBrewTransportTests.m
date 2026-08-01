//
//  BPBrewTransportTests.m
//  CakebrewTests
//
//  The transport seam decides whether brew runs in-process (today) or in the
//  non-sandboxed helper. Getting the default wrong would either break the
//  shipping app or silently bypass the sandbox, so it is pinned here.
//

#import <XCTest/XCTest.h>
#import "BPHomebrewInterface.h"
#import "BPHelperClient.h"

@interface BPBrewTransportTests : XCTestCase
@end

@implementation BPBrewTransportTests

#pragma mark - transport selection

- (void)testUnsandboxedBuildsRunBrewInProcess
{
	XCTAssertEqual([BPHomebrewInterface defaultTransportWhenSandboxed:NO], kBPBrewTransportDirect,
				   @"the shipping Developer ID build must keep running brew directly");
}

- (void)testSandboxedBuildsRouteThroughTheHelper
{
	XCTAssertEqual([BPHomebrewInterface defaultTransportWhenSandboxed:YES], kBPBrewTransportHelper,
				   @"a sandboxed app cannot exec brew itself");
}

- (void)testTestRunIsNotSandboxedSoTheDefaultIsDirect
{
	// Guards the whole existing suite: if this ever flipped, every list-call
	// test would start trying to reach a helper that isn't installed.
	XCTAssertFalse([BPHomebrewInterface isRunningSandboxed]);
	XCTAssertEqual([[BPHomebrewInterface sharedInterface] brewTransport], kBPBrewTransportDirect);
}

#pragma mark - reply/stream reconciliation

- (void)testUndeliveredTailIsNilWhenEverythingStreamed
{
	XCTAssertNil([BPHelperClient undeliveredTailOfOutput:@"abcdef" deliveredLength:6]);
}

- (void)testUndeliveredTailReturnsWhatTheSinkMissed
{
	XCTAssertEqualObjects([BPHelperClient undeliveredTailOfOutput:@"abcdef" deliveredLength:4], @"ef",
						  @"the reply can outrun the last chunks; the tail must still reach the caller");
}

- (void)testUndeliveredTailToleratesOverDelivery
{
	XCTAssertNil([BPHelperClient undeliveredTailOfOutput:@"abc" deliveredLength:99]);
	XCTAssertNil([BPHelperClient undeliveredTailOfOutput:nil deliveredLength:0]);
}

@end
