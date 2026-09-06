//
//  BPMainMenuTests.m
//  CakebrewTests
//
//  The menu bar carried four defects: no Show/Hide Sidebar at all, ⌘F bound
//  twice (so Edit ▸ Find… drew a shortcut it could never receive, because the
//  Formula menu precedes Edit), several untouched Xcode template submenus
//  targeting text actions no view here implements, and a "Preferences…" item
//  contradicting its own window, which is titled "Settings".
//
//  These scan the xib source rather than a built menu: the defects are
//  structural — a duplicate key equivalent, a submenu that shouldn't exist —
//  and a scan names the offending line when it fails. __FILE__ is the
//  compile-time path of this file, so it locates the checkout on CI too.
//

#import <XCTest/XCTest.h>
#import "BPMainWindowController.h"
#import "BPToolbar.h"

// Simulated user-entered package identifiers are intentionally untranslated.
// Limit the analyzer annotation to these two fixed input fixtures.
__attribute__((annotate("returns_localized_nsstring")))
static NSString *BPSearchPackageInput(BOOL cask)
{
	return cask ? @"MockChrome" : @"MockWget";
}

@interface BPSearchToolbarController : NSObject
@property (copy) NSString *lastSearch;
@property NSUInteger searchCount;
- (void)performSearchWithString:(NSString *)search;
@end

@implementation BPSearchToolbarController
- (void)performSearchWithString:(NSString *)search
{
	// Like the real controller, require string semantics, not a control sender.
	self.lastSearch = [search lowercaseString];
	self.searchCount++;
}
@end

@interface BPMainMenuTests : XCTestCase
@end

@implementation BPMainMenuTests

- (NSString *)mainMenuXib
{
	NSString *repoRoot = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSString *path = [repoRoot stringByAppendingPathComponent:@"Cakebrew/Base.lproj/MainMenu.xib"];
	NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
	XCTAssertGreaterThan(contents.length, 0u, @"could not read MainMenu.xib at %@", path);
	return contents;
}

- (NSUInteger)countOfPattern:(NSString *)pattern in:(NSString *)text
{
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
	return [regex numberOfMatchesInString:text options:0 range:NSMakeRange(0, text.length)];
}

#pragma mark - the duplicate Command-F

- (void)testCommandFIsBoundExactlyOnce
{
	// Two items claimed ⌘F. The Formula menu comes first, so Edit ▸ Find… was
	// dead while still advertising the shortcut.
	NSUInteger bindings = [self countOfPattern:@"keyEquivalent=\"f\"" in:[self mainMenuXib]];
	XCTAssertEqual(bindings, 1u, @"⌘F must be claimed by exactly one menu item");
}

- (void)testTheSurvivingCommandFIsSearchForFormula
{
	NSUInteger match = [self countOfPattern:@"title=\"Search for Formula\" keyEquivalent=\"f\"" in:[self mainMenuXib]];
	XCTAssertEqual(match, 1u, @"⌘F should belong to Search for Formula");
}

#pragma mark - dead template submenus

- (void)testTemplateEditSubmenusAreGone
{
	NSString *xib = [self mainMenuXib];
	for (NSString *submenu in @[ @"Find", @"Spelling and Grammar", @"Substitutions", @"Transformations", @"Speech" ])
	{
		NSString *pattern = [NSString stringWithFormat:@"<menu key=\"submenu\" title=\"%@\"", submenu];
		XCTAssertEqual([self countOfPattern:pattern in:xib], 0u,
					   @"the %@ submenu targets text actions no view here implements", submenu);
	}
}

#pragma mark - Settings, not Preferences

- (void)testTheMenuItemMatchesTheWindowItOpens
{
	NSString *xib = [self mainMenuXib];
	XCTAssertEqual([self countOfPattern:@"title=\"Preferences…\"" in:xib], 0u,
				   @"the window this opens is titled Settings, and macOS 13+ says Settings");
	XCTAssertEqual([self countOfPattern:@"title=\"Settings…\"" in:xib], 1u);
}

#pragma mark - Show/Hide Sidebar

- (void)testAMenuItemTogglesTheSidebar
{
	NSString *xib = [self mainMenuXib];
	XCTAssertEqual([self countOfPattern:@"selector=\"toggleSidebar:\"" in:xib], 1u,
				   @"View needs a Show/Hide Sidebar item");
	// AppKit retitles a toggleSidebar: item to Show/Hide to match state, the
	// same way it renames Preferences… to Settings…, so the xib carries the
	// conventional "Show Sidebar" and the rendered title is checked by the UI
	// journey rather than here.
	XCTAssertEqual([self countOfPattern:@"title=\"Show Sidebar\" keyEquivalent=\"s\"" in:xib], 1u,
				   @"the sidebar item should carry the standard ⌃⌘S");
}

- (void)testTheWindowControllerHandlesToggleSidebar
{
	// The split view controller's view is a subview rather than the window's
	// contentViewController, so whether toggleSidebar: reaches it through the
	// responder chain depends on what has focus. The window controller is
	// always in the chain, so it forwards.
	XCTAssertTrue([BPMainWindowController instancesRespondToSelector:@selector(toggleSidebar:)]);
}

- (void)testTheToolbarOffersTheSidebarButton
{
	BPToolbar *toolbar = [[BPToolbar alloc] initWithIdentifier:@"BPMainWindowToolbarTest"];

	XCTAssertTrue([[toolbar toolbarDefaultItemIdentifiers:toolbar] containsObject:NSToolbarToggleSidebarItemIdentifier],
				  @"the sidebar button should be present by default");
	XCTAssertTrue([[toolbar toolbarAllowedItemIdentifiers:toolbar] containsObject:NSToolbarToggleSidebarItemIdentifier]);
}

#pragma mark - toolbar customization

- (NSSearchToolbarItem *)searchItemForToolbar:(BPToolbar *)toolbar
{
	return (NSSearchToolbarItem *)[toolbar toolbar:toolbar
		itemForItemIdentifier:@"toolbarItemSearch" willBeInsertedIntoToolbar:YES];
}

- (void)testSearchUnlockEnablesTheFieldWithoutEnablingInactiveActions
{
	BPToolbar *toolbar = [[BPToolbar alloc] initWithIdentifier:@"SearchEnablement"];
	BPSearchToolbarController *controller = [BPSearchToolbarController new];
	toolbar.controller = controller;
	NSSearchToolbarItem *item = [self searchItemForToolbar:toolbar];
	XCTAssertFalse(item.enabled, @"Search starts locked during the initial load");
	XCTAssertFalse(item.searchField.enabled);
	[toolbar unlockItems];
	[item validate];
	[toolbar validateVisibleItems];
	XCTAssertTrue(item.enabled, @"Search must be available after loading");
	XCTAssertTrue(item.searchField.enabled, @"An existing but disabled field cannot be clicked");
	for (NSString *identifier in @[@"toolbarItemInformation", @"toolbarItemMultiAction"])
	{
		NSToolbarItem *placeholder = [toolbar toolbar:toolbar itemForItemIdentifier:identifier
			willBeInsertedIntoToolbar:YES];
		XCTAssertFalse(placeholder.enabled, @"Inactive slots must stay disabled");
	}
	[toolbar lockItems];
}

- (void)testSearchLockAndUnlockSurviveValidationAndMissingController
{
	BPToolbar *toolbar = [[BPToolbar alloc] initWithIdentifier:@"SearchLocking"];
	BPSearchToolbarController *controller = [BPSearchToolbarController new];
	toolbar.controller = controller;
	NSSearchToolbarItem *item = [self searchItemForToolbar:toolbar];
	[toolbar unlockItems];
	[toolbar lockItems];
	[item validate];
	XCTAssertFalse(item.enabled);
	XCTAssertFalse(item.searchField.enabled);
	[toolbar unlockItems];
	[item validate];
	XCTAssertTrue(item.enabled);
	XCTAssertTrue(item.searchField.enabled);
	toolbar.controller = nil;
	[toolbar unlockItems];
	[item validate];
	XCTAssertFalse(item.enabled, @"Search has no destination without a controller");
	XCTAssertFalse(item.searchField.enabled);
}

- (void)testSearchTextChangesAndSubmissionDeliverStringsToTheController
{
	BPToolbar *toolbar = [[BPToolbar alloc] initWithIdentifier:@"SearchDelivery"];
	BPSearchToolbarController *controller = [BPSearchToolbarController new];
	toolbar.controller = controller;
	[toolbar unlockItems];
	NSSearchField *field = [self searchItemForToolbar:toolbar].searchField;
	XCTAssertEqual(toolbar.searchField, field);
	XCTAssertEqual((id)field.delegate, toolbar);
	field.stringValue = BPSearchPackageInput(NO);
	XCTAssertNoThrow([field.delegate controlTextDidChange:
		[NSNotification notificationWithName:NSControlTextDidChangeNotification object:field]]);
	XCTAssertEqualObjects(controller.lastSearch, @"mockwget");
	XCTAssertEqual(controller.searchCount, 1u);
	field.stringValue = BPSearchPackageInput(YES);
	XCTAssertNotEqual(field.action, NULL, @"Submitting or clearing Search needs a safe action");
	if (field.action != NULL)
	{
		XCTAssertNoThrow([[NSApplication sharedApplication] sendAction:field.action to:field.target from:field]);
	}
	XCTAssertEqualObjects(controller.lastSearch, @"mockchrome");
	XCTAssertEqual(controller.searchCount, 2u);
	field.stringValue = @"";
	if (field.action != NULL)
	{
		XCTAssertNoThrow([[NSApplication sharedApplication] sendAction:field.action to:field.target from:field]);
	}
	XCTAssertEqualObjects(controller.lastSearch, @"", @"Clearing Search must reset the filter");
	[toolbar lockItems];
}

- (void)testToolbarCustomizationIsNotHalfWired
{
	// The toolbar advertised customization while the window vetoed the action
	// and no Customize Toolbar… item existed. Advertising it is the half that
	// goes.
	BPToolbar *toolbar = [[BPToolbar alloc] initWithIdentifier:@"BPMainWindowToolbarTest"];
	XCTAssertFalse(toolbar.allowsUserCustomization,
				   @"either wire customization fully or don't advertise it");
}


#pragma mark - Help that actually helps

- (void)testHelpDoesNotSendShowHelpWithNoHelpBook
{
	// The app ships no help book (no CFBundleHelpBookFolder), so showHelp:
	// only ever produced the system "Help isn't available" alert — on the one
	// menu a confused user reaches for first.
	XCTAssertEqual([self countOfPattern:@"selector=\"showHelp:\"" in:[self mainMenuXib]], 0u);
}

- (void)testHelpOpensTheDocumentation
{
	NSString *xib = [self mainMenuXib];
	XCTAssertEqual([self countOfPattern:@"selector=\"openDocumentation:\"" in:xib], 1u);
	XCTAssertEqual([self countOfPattern:@"title=\"Cakebrew Documentation\"" in:xib], 1u,
				   @"the title should say what the item does, since it opens a web page");
}

@end
