//
//  BPUpgradeArgumentsTests.m
//  CakebrewTests
//
//  "Upgrade All Outdated" used to recycle the named-upgrade API by passing
//  @[@""]. That was harmless while arguments were joined into the shell
//  command string — the empty string simply vanished. Once arguments moved to
//  positional parameters ("$@") to close the injection hole, the empty string
//  survived as a real argv entry and `brew upgrade ''` started failing with
//  "No such file or directory". These tests pin the argv so the operand list
//  can never carry a blank again.
//

#import <XCTest/XCTest.h>
#import "BPHomebrewInterface.h"

@interface BPUpgradeArgumentsTests : XCTestCase
@end

@implementation BPUpgradeArgumentsTests

#pragma mark - upgrading everything

- (void)testUpgradingAllFormulaeSendsNoOperands
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingFormulae:nil],
						  (@[@"upgrade"]),
						  @"bare `brew upgrade` is how you upgrade everything");
}

- (void)testAnEmptySelectionUpgradesEverything
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingFormulae:@[]],
						  (@[@"upgrade"]));
}

- (void)testTheEmptyStringNeverReachesBrew
{
	// The actual regression: this argv used to be @[@"upgrade", @""].
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingFormulae:@[@""]],
						  (@[@"upgrade"]),
						  @"an empty operand makes brew fail with 'No such file or directory'");
}

- (void)testWhitespaceOnlyNamesAreDropped
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingFormulae:(@[@" ", @"\n", @"\t"])],
						  (@[@"upgrade"]));
}

#pragma mark - upgrading a selection

- (void)testNamedFormulaeArePassedThroughInOrder
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingFormulae:(@[@"wget", @"git"])],
						  (@[@"upgrade", @"wget", @"git"]));
}

- (void)testBlanksAreDroppedFromAMixedSelection
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingFormulae:(@[@"wget", @"", @"git"])],
						  (@[@"upgrade", @"wget", @"git"]),
						  @"one blank entry must not turn a targeted upgrade into a failed run");
}

- (void)testSurroundingWhitespaceIsTrimmedFromNames
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingFormulae:@[@"  wget  "]],
						  (@[@"upgrade", @"wget"]));
}

#pragma mark - casks

- (void)testUpgradingAllCasksKeepsTheCaskFlag
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingCasks:nil],
						  (@[@"upgrade", @"--cask"]));
}

- (void)testNamedCasksFollowTheCaskFlag
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingCasks:(@[@"mockchrome", @"mockvscode"])],
						  (@[@"upgrade", @"--cask", @"mockchrome", @"mockvscode"]));
}

- (void)testBlankCaskNamesAreDropped
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUpgradingCasks:(@[@"", @"mockchrome"])],
						  (@[@"upgrade", @"--cask", @"mockchrome"]));
}


#pragma mark - cask uninstall: zap

- (void)testUninstallingACaskWithoutZapLeavesTheFlagOff
{
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUninstallingCask:@"mockchrome" zap:NO],
						  (@[@"uninstall", @"--cask", @"mockchrome"]));
}

- (void)testZapAsksHomebrewToRunTheCasksZapStanza
{
	// Plain uninstall removes the app bundle and deliberately leaves
	// preferences, application support and launch agents behind.
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUninstallingCask:@"mockchrome" zap:YES],
						  (@[@"uninstall", @"--cask", @"--zap", @"mockchrome"]),
						  @"--zap must precede the token, like every other brew flag here");
}

- (void)testABlankCaskTokenIsNeverForwarded
{
	// Same hazard as the upgrade path: a blank operand reaches brew as a real
	// empty argv entry and fails.
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUninstallingCask:@"" zap:YES],
						  (@[@"uninstall", @"--cask", @"--zap"]));
	XCTAssertEqualObjects([BPHomebrewInterface argumentsForUninstallingCask:@"  " zap:NO],
						  (@[@"uninstall", @"--cask"]));
}

@end
