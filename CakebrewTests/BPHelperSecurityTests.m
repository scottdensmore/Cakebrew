//
//  BPHelperSecurityTests.m
//  CakebrewTests
//
//  The helper is a sandbox-escape surface: it runs brew outside the app's
//  sandbox. These tests pin down the code-signing requirements that decide
//  who may talk to it (and who it will talk to).
//

#import <XCTest/XCTest.h>
#import "BPHelperSecurity.h"

@interface BPHelperSecurityTests : XCTestCase
@end

@implementation BPHelperSecurityTests

#pragma mark - identifiers

- (void)testMachServiceNameIsNamespacedUnderTheApp
{
	XCTAssertEqualObjects(BPHelperMachServiceName, @"com.scottdensmore.Cakebrew.Helper");
}

- (void)testHelperIdentifierMatchesTheMachServiceName
{
	// SMAppService looks the agent up by this label; keeping them equal avoids
	// a whole class of registration mismatch bugs.
	XCTAssertEqualObjects(BPHelperIdentifier, BPHelperMachServiceName);
}

#pragma mark - client requirement (who may drive the helper)

- (void)testClientRequirementPinsTheAppIdentifier
{
	NSString *req = [BPHelperSecurity clientCodeSigningRequirement];
	XCTAssertTrue([req containsString:@"identifier \"com.scottdensmore.Cakebrew\""],
				  @"only the Cakebrew app may drive the helper: %@", req);
}

- (void)testClientRequirementPinsTheTeamAndAppleAnchor
{
	NSString *req = [BPHelperSecurity clientCodeSigningRequirement];
	// anchor apple generic + leaf OU == our team: rejects ad-hoc/self-signed
	// builds, which is exactly how the spike's rogue client got in.
	XCTAssertTrue([req containsString:@"anchor apple generic"], @"%@", req);
	XCTAssertTrue([req containsString:@"certificate leaf[subject.OU] = \"27ZDER873F\""], @"%@", req);
}

- (void)testClientRequirementIsNotTriviallyPermissive
{
	NSString *req = [BPHelperSecurity clientCodeSigningRequirement];
	// " or " with surrounding spaces is alternation in the requirement
	// language; a bare "or" substring would also match the "or" inside
	// "anchor", which is why this is spaced.
	XCTAssertFalse([req containsString:@" or "], @"no alternation that could widen the requirement: %@", req);
	XCTAssertTrue([req length] > 40, @"requirement should be a real constraint: %@", req);
}

#pragma mark - helper requirement (who the app will accept as the helper)

- (void)testHelperRequirementPinsTheHelperIdentifierAndTeam
{
	NSString *req = [BPHelperSecurity helperCodeSigningRequirement];
	XCTAssertTrue([req containsString:@"identifier \"com.scottdensmore.Cakebrew.Helper\""], @"%@", req);
	XCTAssertTrue([req containsString:@"anchor apple generic"], @"%@", req);
	XCTAssertTrue([req containsString:@"certificate leaf[subject.OU] = \"27ZDER873F\""], @"%@", req);
}

- (void)testTheTwoRequirementsAreNotInterchangeable
{
	XCTAssertNotEqualObjects([BPHelperSecurity clientCodeSigningRequirement],
							 [BPHelperSecurity helperCodeSigningRequirement],
							 @"each side must pin the other's identifier, not its own");
}

@end
