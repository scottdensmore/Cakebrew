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
#import "BPSideBarController.h"
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


#pragma mark - last selected sidebar row

- (void)testLastSelectedSidebarRowRoundTrips
{
	[BPPreferences setLastSelectedSidebarRow:FormulaeSideBarItemAllCasks];
	XCTAssertEqual([BPPreferences lastSelectedSidebarRow], (NSInteger)FormulaeSideBarItemAllCasks);
}

- (void)testLastSelectedSidebarRowDefaultsToInstalled
{
	// A first launch has nothing stored; the app should open where it always has.
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"BPLastSelectedSidebarRow"];
	XCTAssertEqual([BPPreferences lastSelectedSidebarRow], (NSInteger)FormulaeSideBarItemInstalled);
}

#pragma mark - restoring that row safely

- (void)testAStoredRowIsRestoredWhenItIsStillValid
{
	XCTAssertEqual([BPSideBarController restorableRowFrom:FormulaeSideBarItemServices rowCount:15],
				   FormulaeSideBarItemServices);
}

- (void)testARowPastTheEndFallsBackToInstalled
{
	// Rows are outline indices, so removing a sidebar item can strand a stored
	// value past the end.
	XCTAssertEqual([BPSideBarController restorableRowFrom:99 rowCount:15], FormulaeSideBarItemInstalled);
	XCTAssertEqual([BPSideBarController restorableRowFrom:15 rowCount:15], FormulaeSideBarItemInstalled);
}

- (void)testANegativeRowFallsBackToInstalled
{
	XCTAssertEqual([BPSideBarController restorableRowFrom:-1 rowCount:15], FormulaeSideBarItemInstalled);
}

- (void)testAGroupHeaderRowFallsBackToInstalled
{
	// Category rows are headers, not destinations; restoring onto one would
	// leave the app showing nothing.
	for (NSNumber *group in @[ @(FormulaeSideBarItemFormulaeCategory),
							   @(FormulaeSideBarItemCasksCategory),
							   @(FormulaeSideBarItemToolsCategory) ])
	{
		XCTAssertEqual([BPSideBarController restorableRowFrom:group.integerValue rowCount:15],
					   FormulaeSideBarItemInstalled, @"row %@ is a group header", group);
	}
}

@end
