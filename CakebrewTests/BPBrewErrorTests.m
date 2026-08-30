//
//  BPBrewErrorTests.m
//  CakebrewTests
//
//  Failed operations looked exactly like successful ones: the operation window
//  posted the same "task finished" title and notification whether brew exited 0
//  or not, and brew services failures were dropped entirely. Error construction
//  was also ad hoc — one method string-matched "Error:" prefixes against a
//  domain literal with a magic code.
//
//  Building the error from a (status, output) pair is a pure function, so it is
//  tested without running brew at all.
//

#import <XCTest/XCTest.h>
#import "BPBrewError.h"

@interface BPBrewErrorTests : XCTestCase
@end

@implementation BPBrewErrorTests

- (void)testASuccessfulExitProducesNoError
{
	XCTAssertNil([BPBrewError errorForExitStatus:0 output:@"Everything fine\n"],
				 @"exit 0 is success even when brew printed plenty");
}

- (void)testANonZeroExitCarriesTheStatus
{
	NSError *error = [BPBrewError errorForExitStatus:1 output:@"Error: No such keg\n"];

	XCTAssertNotNil(error);
	XCTAssertEqualObjects(error.domain, BPErrorDomain);
	XCTAssertEqual(error.code, BPBrewErrorNonZeroExit);
	XCTAssertEqual([error.userInfo[BPBrewErrorExitStatusKey] integerValue], 1);
}

- (void)testTheDescriptionQuotesBrewRatherThanInventingWording
{
	// The user needs brew's own words; paraphrasing loses the actionable part.
	NSError *error = [BPBrewError errorForExitStatus:1 output:@"Error: No such keg: /usr/local/Cellar/nope\n"];

	XCTAssertTrue([error.localizedDescription containsString:@"No such keg"],
				  @"got: %@", error.localizedDescription);
}

- (void)testOnlyTheTailOfALongTranscriptIsKept
{
	// An install can print thousands of lines; an alert cannot show them, and
	// the failure is always at the end.
	NSMutableString *output = [NSMutableString string];
	for (NSUInteger i = 0; i < 500; i++)
	{
		[output appendFormat:@"line %lu\n", (unsigned long)i];
	}
	[output appendString:@"Error: it broke\n"];

	NSError *error = [BPBrewError errorForExitStatus:1 output:output];

	XCTAssertTrue([error.localizedDescription containsString:@"Error: it broke"], @"the tail must survive");
	XCTAssertLessThan(error.localizedDescription.length, 2000u, @"the head must not");
	XCTAssertFalse([error.localizedDescription containsString:@"line 0\n"], @"the head must not");
}

- (void)testAFailureWithNoOutputStillDescribesItself
{
	// A crash or a launch failure can leave nothing on either pipe.
	NSError *error = [BPBrewError errorForExitStatus:127 output:@""];

	XCTAssertNotNil(error);
	XCTAssertGreaterThan(error.localizedDescription.length, 0u,
						 @"an empty message would show a blank alert");
	XCTAssertEqual([error.userInfo[BPBrewErrorExitStatusKey] integerValue], 127);
}

- (void)testALaunchFailureIsItsOwnCase
{
	// -1 is what BPTask returns when the process could not be launched at all,
	// which is a different problem from brew rejecting the command.
	NSError *error = [BPBrewError errorForExitStatus:-1 output:@""];

	XCTAssertEqual(error.code, BPBrewErrorLaunchFailed);
}

@end
