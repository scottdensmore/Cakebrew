//
//  BPAccessibilityTests.m
//  CakebrewTests
//
//  The sidebar badges are the app's main information signal and are painted
//  with drawAtPoint:withAttributes:, so nothing about them reached the
//  accessibility tree until BPSidebarBadgeView declared a role and a value.
//

#import <XCTest/XCTest.h>
#import <Cocoa/Cocoa.h>
#import "BPSideBarController.h"

@interface BPAccessibilityTests : XCTestCase
@end

@implementation BPAccessibilityTests

- (void)testTheBadgeIsAnAccessibilityElementWithItsCountAsTheValue
{
	BPSidebarBadgeView *badge = [[BPSidebarBadgeView alloc] initWithFrame:NSMakeRect(0, 0, 30, 16)];
	badge.badgeValue = 42;

	XCTAssertTrue(badge.isAccessibilityElement, @"a view painted with drawAtPoint: is invisible otherwise");
	XCTAssertEqualObjects(badge.accessibilityRole, NSAccessibilityStaticTextRole);
	XCTAssertTrue([[badge.accessibilityValue description] containsString:@"42"],
				  @"the count is the point of the badge: %@", badge.accessibilityValue);
}

- (void)testAZeroBadgeStillAnnouncesItsCount
{
	BPSidebarBadgeView *badge = [[BPSidebarBadgeView alloc] initWithFrame:NSMakeRect(0, 0, 30, 16)];
	badge.badgeValue = 0;

	XCTAssertTrue([[badge.accessibilityValue description] containsString:@"0"]);
}

#pragma mark - Row labels

// "Installed" and "Outdated" each appear under both Formulae and Casks. The
// cell set only the text field's string value, so the two rows were
// indistinguishable to VoiceOver — and the journeys had to disambiguate by
// index, encoding an ordering no test should have to know.

- (void)testARowIsAnnouncedWithItsGroupSoDuplicatesDiffer
{
	NSString *formulae = [BPSideBarController accessibilityLabelForGroup:@"Formulae"
																   title:@"Installed"
																   badge:@3];
	NSString *casks = [BPSideBarController accessibilityLabelForGroup:@"Casks"
																title:@"Installed"
																badge:@2];

	XCTAssertNotEqualObjects(formulae, casks, @"the two Installed rows must not sound alike");
	XCTAssertTrue([formulae containsString:@"Formulae"]);
	XCTAssertTrue([formulae containsString:@"Installed"]);
	XCTAssertTrue([formulae containsString:@"3"], @"the count is the row's main signal");
}

/// -1 is the "no badge" sentinel, not a count. Tools rows carry it.
- (void)testAnAbsentBadgeIsOmittedRatherThanAnnouncedAsMinusOne
{
	NSString *label = [BPSideBarController accessibilityLabelForGroup:@"Tools"
															   title:@"Doctor"
															   badge:@(-1)];

	XCTAssertFalse([label containsString:@"-1"], @"got: %@", label);
	XCTAssertTrue([label containsString:@"Doctor"]);
	XCTAssertTrue([label containsString:@"Tools"]);
}

- (void)testAZeroBadgeIsStillAnnounced
{
	NSString *label = [BPSideBarController accessibilityLabelForGroup:@"Formulae"
															   title:@"Outdated"
															   badge:@0];

	XCTAssertTrue([label containsString:@"0"], @"nothing outdated is worth hearing: %@", label);
}

/// A row with no group is still announced, rather than reading a stray comma.
- (void)testAGrouplessRowIsAnnouncedByTitleAlone
{
	NSString *label = [BPSideBarController accessibilityLabelForGroup:nil title:@"Doctor" badge:@(-1)];

	XCTAssertEqualObjects(label, @"Doctor");
}

/// A missing separator key would be read aloud verbatim between every part.
- (void)testTheLabelNeverLeaksALocalizationKey
{
	NSString *label = [BPSideBarController accessibilityLabelForGroup:@"Casks"
															   title:@"Outdated"
															   badge:@1];

	XCTAssertFalse([label containsString:@"Sidebar_"], @"got: %@", label);
}

#pragma mark - Row identifiers

/// Identifiers address a row and are never read aloud, so they are stable and
/// deliberately unlocalized — a German run has to find the same row.
- (void)testEverySelectableRowHasAUniqueUnlocalizedIdentifier
{
	BPSideBarController *controller = [[BPSideBarController alloc] init];
	NSArray<NSString *> *identifiers = [controller selectableRowAccessibilityIdentifiers];

	XCTAssertEqual(identifiers.count, [NSSet setWithArray:identifiers].count,
				   @"identifiers must be unique: %@", identifiers);
	XCTAssertTrue(identifiers.count >= 12, @"expected every selectable row, got %@", identifiers);

	for (NSString *identifier in identifiers)
	{
		XCTAssertTrue([identifier hasPrefix:@"sidebar."], @"%@ is not namespaced", identifier);
		XCTAssertEqualObjects(identifier, identifier.lowercaseString, @"%@ should be stable and lowercase", identifier);
	}

	XCTAssertTrue([identifiers containsObject:@"sidebar.formulae.installed"], @"%@", identifiers);
	XCTAssertTrue([identifiers containsObject:@"sidebar.casks.installed"], @"%@", identifiers);
}

@end
