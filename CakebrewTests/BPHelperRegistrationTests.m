//
//  BPHelperRegistrationTests.m
//  CakebrewTests
//
//  The helper's registration state drives what the user is told and whether
//  brew operations can run at all, so the mapping from SMAppService's status
//  is pinned here rather than discovered in the UI.
//

#import <XCTest/XCTest.h>
#import <ServiceManagement/ServiceManagement.h>
#import "BPHelperRegistration.h"
#import "BPHomebrewInterface.h"

@interface BPHelperRegistrationTests : XCTestCase
@end

@implementation BPHelperRegistrationTests

#pragma mark - transport gating

- (void)testDirectTransportNeedsNoHelperAtAll
{
	// The shipping build runs brew in-process; the helper is irrelevant and
	// the user must not be nagged to approve anything.
	BPHelperState state = [BPHelperRegistration stateForTransport:kBPBrewTransportDirect
													serviceStatus:SMAppServiceStatusNotRegistered];
	XCTAssertEqual(state, kBPHelperStateNotRequired);
	XCTAssertTrue([BPHelperRegistration stateAllowsBrewOperations:state],
				  @"direct transport must never be blocked by helper state");
}

#pragma mark - status mapping (helper transport)

- (void)testEnabledServiceIsReady
{
	BPHelperState state = [BPHelperRegistration stateForTransport:kBPBrewTransportHelper
													serviceStatus:SMAppServiceStatusEnabled];
	XCTAssertEqual(state, kBPHelperStateReady);
	XCTAssertTrue([BPHelperRegistration stateAllowsBrewOperations:state]);
}

- (void)testRequiresApprovalIsSurfacedAndBlocks
{
	BPHelperState state = [BPHelperRegistration stateForTransport:kBPBrewTransportHelper
													serviceStatus:SMAppServiceStatusRequiresApproval];
	XCTAssertEqual(state, kBPHelperStateNeedsApproval);
	XCTAssertFalse([BPHelperRegistration stateAllowsBrewOperations:state],
				   @"brew cannot run until the user approves the background item");
	XCTAssertTrue([BPHelperRegistration stateOffersLoginItemsShortcut:state],
				  @"this is the one state where pointing at Login Items helps");
}

- (void)testNotRegisteredBlocksAndDoesNotOfferLoginItems
{
	BPHelperState state = [BPHelperRegistration stateForTransport:kBPBrewTransportHelper
													serviceStatus:SMAppServiceStatusNotRegistered];
	XCTAssertEqual(state, kBPHelperStateNotRegistered);
	XCTAssertFalse([BPHelperRegistration stateAllowsBrewOperations:state]);
	XCTAssertFalse([BPHelperRegistration stateOffersLoginItemsShortcut:state],
				   @"nothing to approve yet — the app should register first");
}

- (void)testNotFoundIsUnavailable
{
	// Happens when the app isn't where launchd expects it (e.g. run from the
	// Downloads folder instead of /Applications).
	BPHelperState state = [BPHelperRegistration stateForTransport:kBPBrewTransportHelper
													serviceStatus:SMAppServiceStatusNotFound];
	XCTAssertEqual(state, kBPHelperStateUnavailable);
	XCTAssertFalse([BPHelperRegistration stateAllowsBrewOperations:state]);
}

- (void)testUnknownFutureStatusFailsClosed
{
	BPHelperState state = [BPHelperRegistration stateForTransport:kBPBrewTransportHelper
													serviceStatus:(SMAppServiceStatus)99];
	XCTAssertEqual(state, kBPHelperStateUnavailable, @"an unrecognised status must not read as ready");
	XCTAssertFalse([BPHelperRegistration stateAllowsBrewOperations:state]);
}

#pragma mark - user-facing description

- (void)testEveryStateHasANonEmptyDescription
{
	NSArray<NSNumber *> *states = @[ @(kBPHelperStateNotRequired), @(kBPHelperStateReady),
									 @(kBPHelperStateNeedsApproval), @(kBPHelperStateNotRegistered),
									 @(kBPHelperStateUnavailable) ];
	for (NSNumber *state in states) {
		NSString *text = [BPHelperRegistration localizedDescriptionForState:state.integerValue];
		XCTAssertTrue(text.length > 0, @"state %@ needs something to show the user", state);
	}
}

#pragma mark - identifiers

- (void)testPlistNameMatchesTheRegisteredIdentifier
{
	// SMAppService looks the agent up by plist name; a mismatch here is a
	// silent "notFound" at runtime.
	XCTAssertEqualObjects([BPHelperRegistration agentPlistName], @"com.scottdensmore.Cakebrew.Helper.plist");
}

@end
