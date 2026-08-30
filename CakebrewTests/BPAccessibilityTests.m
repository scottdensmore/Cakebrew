//
//  BPAccessibilityTests.m
//  CakebrewTests
//
//  The app had no accessibility wiring at all. The sidebar badges — its main
//  information signal — are painted with drawAtPoint:withAttributes:, so they
//  did not exist for VoiceOver, and "Installed" and "Outdated" each appear
//  under both Formulae and Casks, so the rows were indistinguishable. That same
//  ambiguity is why the UI tests had to disambiguate by index.
//

#import <XCTest/XCTest.h>
#import "BPSideBarController.h"

@interface BPAccessibilityTests : XCTestCase
@end

@implementation BPAccessibilityTests

- (void)testARowIsAnnouncedWithItsGroupSoDuplicatesAreDistinguishable
{
	NSString *formulae = [BPSideBarController accessibilityLabelForGroup:@"Formulae" title:@"Installed" badge:@42];
	NSString *casks = [BPSideBarController accessibilityLabelForGroup:@"Casks" title:@"Installed" badge:@7];

	XCTAssertNotEqualObjects(formulae, casks, @"the two Installed rows must not read identically");
	XCTAssertTrue([formulae hasPrefix:@"Formulae"], @"the group comes first: %@", formulae);
	XCTAssertTrue([formulae containsString:@"Installed"]);
}

- (void)testTheBadgeCountIsPartOfTheAnnouncement
{
	NSString *label = [BPSideBarController accessibilityLabelForGroup:@"Formulae" title:@"Outdated" badge:@3];
	XCTAssertTrue([label containsString:@"3"], @"the count is the point of the badge: %@", label);
}

- (void)testARowWithNoBadgeIsNotGivenACount
{
	// -1 is the sentinel for "no badge"; announcing "-1 items" would be worse
	// than announcing nothing.
	NSString *label = [BPSideBarController accessibilityLabelForGroup:@"Tools" title:@"Doctor" badge:@(-1)];

	XCTAssertFalse([label containsString:@"-1"], @"got: %@", label);
	XCTAssertTrue([label containsString:@"Doctor"]);
}

- (void)testATopLevelRowIsAnnouncedWithoutAGroup
{
	NSString *label = [BPSideBarController accessibilityLabelForGroup:nil title:@"Doctor" badge:@(-1)];
	XCTAssertEqualObjects(label, @"Doctor");
}

- (void)testIdentifiersAreStableAndDistinguishTheDuplicateRows
{
	XCTAssertEqualObjects([BPSideBarController accessibilityIdentifierForGroup:@"Formulae" title:@"Installed"],
						  @"sidebar.formulae.installed");
	XCTAssertEqualObjects([BPSideBarController accessibilityIdentifierForGroup:@"Casks" title:@"Installed"],
						  @"sidebar.casks.installed");
	XCTAssertEqualObjects([BPSideBarController accessibilityIdentifierForGroup:@"Formulae" title:@"All Formulae"],
						  @"sidebar.formulae.all-formulae");
}

- (void)testIdentifiersAreNotLocalized
{
	// An identifier addresses a row; localizing it would break the UI tests in
	// every language but English.
	NSString *identifier = [BPSideBarController accessibilityIdentifierForGroup:@"Formulae" title:@"Installed"];
	XCTAssertEqualObjects(identifier, identifier.lowercaseString);
	XCTAssertFalse([identifier containsString:@" "]);
}

@end
