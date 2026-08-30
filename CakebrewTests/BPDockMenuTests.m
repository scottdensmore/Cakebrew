//
//  BPDockMenuTests.m
//  CakebrewTests
//
//  Right-clicking the Dock icon offered only the system defaults. The three
//  things a user wants from a package manager without switching to it — check,
//  upgrade everything, jump to what is outdated — were not reachable.
//
//  Dock menus are not XCUITest-drivable on the headless runner, so the menu's
//  shape and, more importantly, the mapping from menu item to the controller
//  action it fires are pinned here. The mapping is the part that rots: renaming
//  an IBAction leaves a Dock item that silently does nothing.
//

#import <XCTest/XCTest.h>
#import "BPDockMenu.h"
#import <objc/runtime.h>

@interface BPDockMenuTests : XCTestCase
@end

@implementation BPDockMenuTests

#pragma mark - Shape

- (void)testOffersTheThreeActionsInOrder
{
	NSMenu *menu = [BPDockMenu dockMenuWithTarget:self enabled:YES];

	NSArray<NSNumber *> *tags = [menu.itemArray valueForKey:@"tag"];

	XCTAssertEqualObjects(tags, (@[ @(BPDockMenuItemCheckForUpdates),
									@(BPDockMenuItemUpgradeAllOutdated),
									@(BPDockMenuItemShowOutdated) ]),
						  @"the Dock menu should offer check, upgrade all, and jump to Outdated");
}

- (void)testEveryItemIsTitledAndTargeted
{
	NSMenu *menu = [BPDockMenu dockMenuWithTarget:self enabled:YES];

	for (NSMenuItem *item in menu.itemArray)
	{
		XCTAssertTrue(item.title.length > 0, @"a Dock item needs a title");
		XCTAssertEqualObjects(item.target, self);
		XCTAssertTrue(item.isEnabled);
	}
}

/// Every title key really exists. NSLocalizedString returns the key when the
/// string is missing, so an unshipped key becomes "Dock_Show_Outdated" in the
/// Dock. Checked against the source .strings rather than the bundle: this test
/// bundle carries no Localizable.strings, so a lookup here proves nothing.
/// BPLocalizationParityTests covers the other five locales.
- (void)testEveryTitleKeyIsInTheStringsFile
{
	NSString *repoRoot = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSString *path = [repoRoot stringByAppendingPathComponent:@"Cakebrew/en.lproj/Localizable.strings"];
	NSString *english = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];

	XCTAssertTrue(english.length > 0, @"could not read en.lproj/Localizable.strings at %@", path);

	NSMenu *menu = [BPDockMenu dockMenuWithTarget:self enabled:YES];

	for (NSMenuItem *item in menu.itemArray)
	{
		NSString *key = [BPDockMenu localizationKeyForItem:(BPDockMenuItem)item.tag];
		XCTAssertNotNil(key, @"item with tag %ld has no title key", (long)item.tag);

		NSString *quoted = [NSString stringWithFormat:@"\"%@\" =", key];
		XCTAssertTrue([english containsString:quoted], @"%@ is not in en.lproj", key);
	}
}

/// With Homebrew missing, every one of these actions would fail. The Dock menu
/// is reachable when the app is in the background and cannot show the app's own
/// "Homebrew not installed" state, so the items are simply off.
- (void)testItemsAreDisabledWhenHomebrewIsUnavailable
{
	NSMenu *menu = [BPDockMenu dockMenuWithTarget:self enabled:NO];

	for (NSMenuItem *item in menu.itemArray)
	{
		XCTAssertFalse(item.isEnabled, @"%@ should be off without Homebrew", item.title);
	}
}

/// NSMenu enables items by asking the target to validate them. These are built
/// enabled or not by hand, so automatic enabling has to be off or AppKit
/// overrides the decision above.
- (void)testMenuDoesNotAutoEnableItems
{
	XCTAssertFalse([BPDockMenu dockMenuWithTarget:self enabled:NO].autoenablesItems);
}

#pragma mark - The mapping that rots

/// Each Dock item maps to a selector that is actually part of the contract the
/// view controller conforms to. Renaming an IBAction then breaks the build
/// (conformance) rather than shipping a Dock item that does nothing; this pins
/// the other half — that the mapping points into that contract at all.
- (void)testEveryItemMapsIntoTheActionsProtocol
{
	NSArray<NSNumber *> *items = @[ @(BPDockMenuItemCheckForUpdates),
									@(BPDockMenuItemUpgradeAllOutdated),
									@(BPDockMenuItemShowOutdated) ];

	for (NSNumber *item in items)
	{
		SEL action = [BPDockMenu controllerActionForItem:(BPDockMenuItem)item.integerValue];
		XCTAssertTrue(action != NULL, @"item %@ has no action", item);

		struct objc_method_description described =
			protocol_getMethodDescription(@protocol(BPDockMenuActions), action, YES, YES);

		XCTAssertTrue(described.name != NULL,
					  @"%@ is not a BPDockMenuActions action", NSStringFromSelector(action));
	}
}

/// Every action in the protocol is reachable from the menu. Adding one without
/// a Dock item is dead code; this catches the half the mapping test cannot.
- (void)testEveryProtocolActionIsOfferedByTheMenu
{
	unsigned int count = 0;
	struct objc_method_description *described =
		protocol_copyMethodDescriptionList(@protocol(BPDockMenuActions), YES, YES, &count);

	NSMenu *menu = [BPDockMenu dockMenuWithTarget:self enabled:YES];

	NSMutableSet<NSString *> *offered = [NSMutableSet set];
	for (NSMenuItem *item in menu.itemArray)
	{
		SEL action = [BPDockMenu controllerActionForItem:(BPDockMenuItem)item.tag];
		if (action) [offered addObject:NSStringFromSelector(action)];
	}

	for (unsigned int i = 0; i < count; i++)
	{
		XCTAssertTrue([offered containsObject:NSStringFromSelector(described[i].name)],
					  @"%@ is declared but no Dock item fires it", NSStringFromSelector(described[i].name));
	}

	free(described);
}

- (void)testAnUnknownItemMapsToNothing
{
	XCTAssertTrue([BPDockMenu controllerActionForItem:(BPDockMenuItem)9999] == NULL);
}

@end
