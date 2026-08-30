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

@end
