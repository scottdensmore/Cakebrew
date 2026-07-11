//
//  BPPreferencesTests.m
//  CakebrewTests
//
//  Tests for BPPreferences (registered defaults + typed accessors) and for
//  the one setting with immediate effect: greedy cask upgrades threading
//  --greedy into the outdated-casks list call.
//

#import <XCTest/XCTest.h>
#import "BPPreferences.h"
#import "BPFormula.h"

@interface BPHomebrewInterfaceListCall : NSObject
@property (strong, readonly) NSArray *arguments;
@end

@interface BPHomebrewInterfaceListCallOutdatedCasks : BPHomebrewInterfaceListCall
- (instancetype)init;
@end

@interface BPPreferencesTests : XCTestCase
@end

@implementation BPPreferencesTests

- (void)setUp
{
	[super setUp];
	[BPPreferences registerDefaults];
}

- (void)tearDown
{
	// Remove any explicit values so tests observe the registered defaults.
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults removeObjectForKey:kBPBackgroundCheckEnabledKey];
	[defaults removeObjectForKey:kBPBackgroundCheckIntervalKey];
	[defaults removeObjectForKey:kBPGreedyCaskUpgradesKey];
	[super tearDown];
}

- (void)testRegisteredDefaults
{
	XCTAssertTrue([BPPreferences backgroundCheckEnabled], @"background checking defaults to on");
	XCTAssertEqual([BPPreferences backgroundCheckInterval], 21600.0, @"default interval is 6 hours");
	XCTAssertFalse([BPPreferences greedyCaskUpgrades], @"greedy cask upgrades default to off");
}

- (void)testSettersRoundTrip
{
	[BPPreferences setBackgroundCheckEnabled:NO];
	XCTAssertFalse([BPPreferences backgroundCheckEnabled]);

	[BPPreferences setBackgroundCheckInterval:3600.0];
	XCTAssertEqual([BPPreferences backgroundCheckInterval], 3600.0);

	[BPPreferences setGreedyCaskUpgrades:YES];
	XCTAssertTrue([BPPreferences greedyCaskUpgrades]);
}

- (void)testOutdatedCasksCallOmitsGreedyByDefault
{
	BPHomebrewInterfaceListCallOutdatedCasks *call = [BPHomebrewInterfaceListCallOutdatedCasks new];
	XCTAssertFalse([call.arguments containsObject:@"--greedy"]);
}

- (void)testOutdatedCasksCallAddsGreedyWhenEnabled
{
	[BPPreferences setGreedyCaskUpgrades:YES];

	BPHomebrewInterfaceListCallOutdatedCasks *call = [BPHomebrewInterfaceListCallOutdatedCasks new];
	XCTAssertEqualObjects(call.arguments, (@[ @"outdated", @"--cask", @"--verbose", @"--greedy" ]));
}

@end
