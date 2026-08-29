//
//  BPLocalizedStringsTests.m
//  CakebrewTests
//
//  Two user-visible mappings were wrong in ways only a non-English user would
//  notice: the Pinned list had no case at all, so it kept whatever description
//  the previously selected list had left behind, and the Services column
//  printed brew's raw JSON tokens (none/started/stopped) rather than anything
//  localized.
//
//  Both are pure lookups, so they are tested by key rather than by rendered
//  string — the test bundle has no Localizable.strings, and keys are what must
//  stay in sync with the six .lproj files.
//

#import <XCTest/XCTest.h>
#import "BPSideBarController.h"
#import "BPService.h"

// statusFromString: is private to BPService.m (compiled into this target);
// re-declared so the round-trip test can drive brew's raw tokens through it.
@interface BPService (BPLocalizedStringsTestsPrivate)
+ (BPServiceStatus)statusFromString:(NSString *)status;
@end

@interface BPLocalizedStringsTests : XCTestCase
@end

@implementation BPLocalizedStringsTests

#pragma mark - sidebar description

- (void)testEverySelectableSidebarRowHasItsOwnDescription
{
	// Pinned was the one missing, but the point is that none may be absent:
	// a missing case leaves the previous row's text on screen.
	NSDictionary<NSNumber *, NSString *> *expected = @{
		@(FormulaeSideBarItemInstalled):      @"Sidebar_Info_Installed",
		@(FormulaeSideBarItemOutdated):       @"Sidebar_Info_Outdated",
		@(FormulaeSideBarItemAll):            @"Sidebar_Info_All",
		@(FormulaeSideBarItemLeaves):         @"Sidebar_Info_Leaves",
		@(FormulaeSideBarItemPinned):         @"Sidebar_Info_Pinned",
		@(FormulaeSideBarItemRepositories):   @"Sidebar_Info_Repos",
		@(FormulaeSideBarItemInstalledCasks): @"Sidebar_Info_Casks",
		@(FormulaeSideBarItemOutdatedCasks):  @"Sidebar_Info_OutdatedCasks",
		@(FormulaeSideBarItemAllCasks):       @"Sidebar_Info_AllCasks",
		@(FormulaeSideBarItemDoctor):         @"Sidebar_Info_Doctor",
		@(FormulaeSideBarItemUpdate):         @"Sidebar_Info_Update",
		@(FormulaeSideBarItemServices):       @"Sidebar_Info_Services",
	};

	[expected enumerateKeysAndObjectsUsingBlock:^(NSNumber *row, NSString *key, BOOL *stop) {
		XCTAssertEqualObjects([BPSideBarController infoKeyForRow:row.integerValue], key,
							  @"row %@", row);
	}];
}

- (void)testGroupHeaderRowsHaveNoDescription
{
	// Headers aren't selectable, so nil is correct — and the caller clears the
	// label rather than leaving the previous row's text up.
	XCTAssertNil([BPSideBarController infoKeyForRow:FormulaeSideBarItemFormulaeCategory]);
	XCTAssertNil([BPSideBarController infoKeyForRow:FormulaeSideBarItemCasksCategory]);
	XCTAssertNil([BPSideBarController infoKeyForRow:FormulaeSideBarItemToolsCategory]);
}

- (void)testAnUnknownRowHasNoDescription
{
	XCTAssertNil([BPSideBarController infoKeyForRow:99]);
	XCTAssertNil([BPSideBarController infoKeyForRow:-1]);
}

#pragma mark - service status

- (void)testEveryServiceStatusHasALocalizedName
{
	NSDictionary<NSNumber *, NSString *> *expected = @{
		@(kBPServiceStatusNone):      @"Services_Status_None",
		@(kBPServiceStatusStarted):   @"Services_Status_Started",
		@(kBPServiceStatusStopped):   @"Services_Status_Stopped",
		@(kBPServiceStatusError):     @"Services_Status_Error",
		@(kBPServiceStatusScheduled): @"Services_Status_Scheduled",
		@(kBPServiceStatusUnknown):   @"Services_Status_Unknown",
	};

	[expected enumerateKeysAndObjectsUsingBlock:^(NSNumber *status, NSString *key, BOOL *stop) {
		XCTAssertEqualObjects([BPService localizationKeyForStatus:status.integerValue], key,
							  @"status %@", status);
	}];
}

- (void)testAnUnrecognisedStatusFallsBackToUnknown
{
	// brew adding a new status must not print a raw token.
	XCTAssertEqualObjects([BPService localizationKeyForStatus:(BPServiceStatus)42], @"Services_Status_Unknown");
}

- (void)testTheStatusNameNeverEchoesBrewsRawToken
{
	for (NSString *raw in @[ @"none", @"started", @"stopped", @"error", @"scheduled" ])
	{
		BPServiceStatus status = [BPService statusFromString:raw];
		NSString *name = [BPService localizedNameForStatus:status];
		XCTAssertNotEqualObjects(name, raw, @"%@ reached the UI unlocalized", raw);
	}
}

@end
