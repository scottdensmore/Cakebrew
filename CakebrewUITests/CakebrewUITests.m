//
//  CakebrewUITests.m
//  CakebrewUITests
//
//  End-to-end UI tests that drive the real app via XCUITest.
//

#import <XCTest/XCTest.h>

@interface CakebrewUITests : XCTestCase
@property (strong) XCUIApplication *app;
@end

@implementation CakebrewUITests

- (void)setUp
{
	[super setUp];
	self.continueAfterFailure = NO;
	self.app = [[XCUIApplication alloc] init];
}

- (void)tearDown
{
	[self.app terminate];
	self.app = nil;
	[super tearDown];
}

// Launch the app with the given arguments and wait for its main window.
- (void)launchWithArguments:(NSArray<NSString *> *)arguments
{
	// The app now reopens on the sidebar row the user last used, which makes a
	// launch depend on whatever the previous test left behind. Pin it through
	// the argument domain (which outranks stored defaults) so every journey
	// starts on Installed; testReopensOnTheLastUsedSidebarRow overrides it
	// deliberately to exercise the restore.
	// Both of these change what the app shows at launch, so both are pinned
	// through the argument domain rather than inherited from whatever the last
	// run (or the developer's own session) left stored.
	NSArray<NSString *> *pinned = @[ @"-BPLastSelectedSidebarRow", @"1",
									 @"-BPSortColumnIdentifier", @"" ];
	BOOL alreadyPinned = [arguments containsObject:@"-BPLastSelectedSidebarRow"];
	self.app.launchArguments = alreadyPinned ? arguments : [arguments arrayByAddingObjectsFromArray:pinned];
	[self.app launch];
	XCTAssertTrue([self.app.windows.firstMatch waitForExistenceWithTimeout:30.0],
				  @"the main window should appear after launch");

	// A test that pins a different starting row is not going to land on the
	// Installed list, so the settle-wait below would never be satisfied.
	NSUInteger rowIndex = [arguments indexOfObject:@"-BPLastSelectedSidebarRow"];
	BOOL startsOnInstalled = (rowIndex == NSNotFound) ||
							 (rowIndex + 1 >= arguments.count) ||
							 [arguments[rowIndex + 1] isEqualToString:@"1"];
	if (!startsOnInstalled) {
		return;
	}

	// Under the mock, wait for the initial reload to settle before tests
	// navigate: homebrewManagerFinishedUpdating reloads the sidebar and
	// re-selects the last selection, which can clobber a click that lands
	// mid-reload (the source of moving sidebar-navigation flakes on CI).
	// The launch view is Installed, so mockwget rendering means the initial
	// refresh cycle is done.
	if ([arguments containsObject:@"-BPMockBrew"]) {
		XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:30.0],
					  @"the initial Installed list should render after launch");
	}
}

- (XCUIElement *)sidebar
{
	XCUIElement *sidebar = self.app.outlines.firstMatch;
	XCTAssertTrue([sidebar waitForExistenceWithTimeout:30.0], @"the sidebar outline should appear");
	return sidebar;
}

// Dismiss a confirmation alert sheet with Escape. Avoids matching the ambiguous
// "Cancel" button (the toolbar search field also exposes one) and leaves a clean
// state for teardown.
- (void)dismissConfirmationSheet
{
	[self.app typeKey:XCUIKeyboardKeyEscape modifierFlags:XCUIKeyModifierNone];
}

#pragma mark - Launch / chrome

// Smoke test: the app launches and presents its main window.
- (void)testAppLaunchesAndShowsMainWindow
{
	[self launchWithArguments:@[]];
}

#pragma mark - Sidebar navigation journeys

// Journey: the sidebar presents every navigation destination.
// Runs with the mock: a real-brew launch spawns a full `brew` reload whose
// subprocesses outlive the test when the app is terminated, and the orphaned
// work has caused timeouts in whichever mock test runs next on CI.
- (void)testSidebarShowsAllNavigationItems
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];
	NSArray<NSString *> *items = @[ @"Installed", @"Outdated", @"All Formulae",
									@"Leaves", @"Repositories", @"Doctor", @"Update" ];
	for (NSString *item in items) {
		XCTAssertTrue([sidebar.staticTexts[item] waitForExistenceWithTimeout:15.0],
					  @"the sidebar should show the %@ item", item);
	}
}

// Journey: selecting a Tools item switches the content to that tool's view.
// Mock-launched for the same reason as testSidebarShowsAllNavigationItems.
- (void)testNavigatingToToolViewsFromSidebar
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	XCUIElement *doctorItem = sidebar.staticTexts[@"Doctor"];
	XCTAssertTrue([doctorItem waitForExistenceWithTimeout:15.0], @"Doctor item should exist");
	[doctorItem click];
	XCTAssertTrue([self.app.staticTexts[@"Homebrew Doctor"] waitForExistenceWithTimeout:15.0],
				  @"selecting Doctor should show the Homebrew Doctor view");

	XCUIElement *updateItem = sidebar.staticTexts[@"Update"];
	XCTAssertTrue([updateItem waitForExistenceWithTimeout:15.0], @"Update item should exist");
	[updateItem click];
	XCTAssertTrue([self.app.staticTexts[@"Homebrew Updater"] waitForExistenceWithTimeout:15.0],
				  @"selecting Update should show the Homebrew Updater view");
}

#pragma mark - Mock-brew data journeys

// Formula names render as NSTextField cells in the table, so the displayed name
// is the element's value rather than its label — match on value.
- (XCUIElement *)formulaCellWithName:(NSString *)name
{
	// BEGINSWITH (not ==) so a pinned formula's cell — whose value is the name
	// followed by the pin symbol — still matches.
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value BEGINSWITH %@", name];
	return [[self.app.textFields matchingPredicate:predicate] firstMatch];
}

// Journey: launched with the mock brew interface, the Installed list populates
// with the fixture formulae instead of whatever is on the host.
- (void)testInstalledListShowsMockFormulae
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:30.0],
				  @"the mock installed list should populate the formula table");
	XCTAssertTrue([[self formulaCellWithName:@"mockgit"] waitForExistenceWithTimeout:15.0],
				  @"the mock installed list should include mockgit");
}

// Journey: selecting a not-installed formula offers Install in the toolbar.
- (void)testNotInstalledFormulaOffersInstall
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	[sidebar.staticTexts[@"All Formulae"] click];
	XCUIElement *htop = [self formulaCellWithName:@"mockhtop"];
	BOOL htopAppeared = [htop waitForExistenceWithTimeout:30.0];
	if (!htopAppeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(htopAppeared, @"mockhtop should be listed under All Formulae");
	[htop click];

	XCUIElement *installButton = self.app.buttons[@"Install Formula"];
	BOOL appeared = [installButton waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"selecting a not-installed formula should offer Install in the toolbar");
}

// Journey: clicking Install on a not-installed formula asks for confirmation.
- (void)testInstallPresentsConfirmationDialog
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	[sidebar.staticTexts[@"All Formulae"] click];
	XCUIElement *htop = [self formulaCellWithName:@"mockhtop"];
	XCTAssertTrue([htop waitForExistenceWithTimeout:30.0], @"mockhtop should be listed under All Formulae");
	[htop click];

	XCUIElement *installButton = self.app.buttons[@"Install Formula"];
	XCTAssertTrue([installButton waitForExistenceWithTimeout:15.0], @"Install should be offered");
	[installButton click];

	// installFormula: presents a Yes / Cancel confirmation.
	XCUIElement *yesButton = self.app.buttons[@"Yes"];
	BOOL confirmationAppeared = [yesButton waitForExistenceWithTimeout:15.0];
	if (!confirmationAppeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(confirmationAppeared, @"clicking Install should present a Yes/Cancel confirmation");

	// Cancel so the test doesn't proceed into the install operation.
	[self dismissConfirmationSheet];
}

// Journey: selecting an installed formula offers Uninstall in the toolbar.
- (void)testInstalledFormulaOffersUninstall
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	// The Installed list is selected by default; mockwget is installed.
	XCUIElement *wget = [self formulaCellWithName:@"mockwget"];
	XCTAssertTrue([wget waitForExistenceWithTimeout:30.0], @"mockwget should be in the Installed list");
	[wget click];

	XCUIElement *uninstallButton = self.app.buttons[@"Uninstall Formula"];
	BOOL appeared = [uninstallButton waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"selecting an installed formula should offer Uninstall in the toolbar");
}

// Journey: the Formula menu exposes Pin / Unpin items (bindings load without
// crashing). Presence — not enabled state — is asserted: disabled menu items
// still exist in the tree, so this guards the xib wiring regardless of selection.
- (void)testFormulaMenuExposesPinAndUnpin
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	// Select an installed formula so the pin items apply to a real selection.
	XCUIElement *wget = [self formulaCellWithName:@"mockwget"];
	XCTAssertTrue([wget waitForExistenceWithTimeout:30.0], @"mockwget should be in the Installed list");
	[wget click];

	[self.app.menuBars.menuBarItems[@"Formula"] click];

	XCUIElement *pinItem = self.app.menuItems[@"Pin Formula"];
	BOOL pinAppeared = [pinItem waitForExistenceWithTimeout:10.0];
	if (!pinAppeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(pinAppeared, @"Formula menu should contain a Pin Formula item");
	XCTAssertTrue(self.app.menuItems[@"Unpin Formula"].exists, @"Formula menu should contain an Unpin Formula item");

	[self.app typeKey:XCUIKeyboardKeyEscape modifierFlags:XCUIKeyModifierNone];
}

// Journey: selecting a formula shows the "Required by" (dependents) row in the
// detail pane. Guards that the new BPSelectedFormula.xib row loads at runtime.
- (void)testDetailPaneShowsRequiredByRow
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *wget = [self formulaCellWithName:@"mockwget"];
	XCTAssertTrue([wget waitForExistenceWithTimeout:30.0], @"mockwget should be in the Installed list");
	[wget click];

	XCUIElement *requiredByLabel = self.app.staticTexts[@"Required by:"];
	BOOL appeared = [requiredByLabel waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the detail pane should show the Required by row");
}

// Journey: selecting a pinned formula shows the "Pinned" row in the detail pane.
// The mock reports mockgit as pinned (its `brew list --pinned` fixture).
- (void)testDetailPaneShowsPinnedRowForPinnedFormula
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *git = [self formulaCellWithName:@"mockgit"];
	XCTAssertTrue([git waitForExistenceWithTimeout:30.0], @"mockgit should be in the Installed list");
	[git click];

	// The row is hidden unless the formula is pinned, so its presence in the
	// accessibility tree confirms both the xib row and the isFormulaPinned wiring.
	XCUIElement *pinnedLabel = self.app.staticTexts[@"Pinned:"];
	BOOL appeared = [pinnedLabel waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the detail pane should show the Pinned row for a pinned formula");
}

// Journey: the Pinned sidebar section lists only pinned formulae.
- (void)testPinnedSidebarSectionListsPinnedFormulae
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	// The mock pins mockgit (its `brew list --pinned` fixture).
	[self.sidebar.staticTexts[@"Pinned"] click];

	XCUIElement *git = [self formulaCellWithName:@"mockgit"];
	BOOL appeared = [git waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the Pinned section should list mockgit");
	XCTAssertFalse([self formulaCellWithName:@"mockwget"].exists,
				   @"unpinned formulae should not appear in the Pinned section");
}

// Journey: the Casks section lists installed casks (browse-only for now).
- (void)testCasksSidebarSectionListsInstalledCasks
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	// The Casks group has its own "Installed" child; the sidebar shows two
	// "Installed" rows (formulae + casks), so click the last match.
	XCUIElement *sidebar = self.sidebar;
	XCUIElementQuery *installedRows = [sidebar.staticTexts matchingIdentifier:@"Installed"];
	XCTAssertTrue([installedRows.firstMatch waitForExistenceWithTimeout:30.0], @"sidebar should load");
	XCTAssertEqual(installedRows.count, 2u, @"expected Installed under both Formulae and Casks");
	[[installedRows elementBoundByIndex:1] click];

	XCUIElement *chrome = [self formulaCellWithName:@"mockchrome"];
	BOOL appeared = [chrome waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the Casks section should list mockchrome");
	XCTAssertTrue([self formulaCellWithName:@"mockvscode"].exists, @"the Casks section should list mockvscode");
	XCTAssertFalse([self formulaCellWithName:@"mockwget"].exists,
				   @"formulae should not appear in the Casks section");
}

// Journey: the Outdated casks section lists the outdated cask and offers
// Update, which asks for confirmation (dispatches to `upgrade --cask`).
- (void)testOutdatedCaskOffersUpdateWithConfirmation
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	// Two "Outdated" rows exist (Formulae + Casks); the casks one is second.
	XCUIElement *sidebar = self.sidebar;
	XCUIElementQuery *outdatedRows = [sidebar.staticTexts matchingIdentifier:@"Outdated"];
	XCTAssertTrue([outdatedRows.firstMatch waitForExistenceWithTimeout:30.0], @"sidebar should load");
	XCTAssertEqual(outdatedRows.count, 2u, @"expected Outdated under both Formulae and Casks");
	[[outdatedRows elementBoundByIndex:1] click];

	XCUIElement *chrome = [self formulaCellWithName:@"mockchrome"];
	BOOL appeared = [chrome waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the outdated cask should be listed");
	[chrome click];

	XCUIElement *updateButton = self.app.buttons[@"Update Formula"];
	XCTAssertTrue([updateButton waitForExistenceWithTimeout:15.0],
				  @"selecting an outdated cask should offer Update in the toolbar");
	[updateButton click];

	XCUIElement *yesButton = self.app.buttons[@"Yes"];
	XCTAssertTrue([yesButton waitForExistenceWithTimeout:15.0],
				  @"clicking Update on a cask should present a Yes/Cancel confirmation");

	// Cancel so the test doesn't proceed into the operation.
	[self dismissConfirmationSheet];
}

// Journey: Preferences opens from the app menu and shows the settings.
/// Waits for the sidebar to reach the collapsed (or expanded) state.
///
/// Measured by width rather than -isHittable: the CI runner's window is never
/// key, so hit testing reports false regardless of whether the sidebar is
/// showing. A collapsed NSSplitViewItem either drops out of the tree or reports
/// zero width.
- (BOOL)waitForSidebar:(XCUIElement *)sidebar collapsed:(BOOL)collapsed timeout:(NSTimeInterval)timeout
{
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
	while ([deadline timeIntervalSinceNow] > 0) {
		BOOL isCollapsed = !sidebar.exists || sidebar.frame.size.width < 1.0;
		if (isCollapsed == collapsed) {
			return YES;
		}
		[NSThread sleepForTimeInterval:0.25];
	}
	return NO;
}

// Journey: the About window credits only code the app actually ships.
//
// Sparkle was removed from Cakebrew but stayed in Credits.rtf for years —
// shipping an attribution for code that isn't there is a licensing-accuracy
// problem, not just a stale string.
- (void)testAboutWindowCreditsOnlyShippedCode
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	[self.app.menuBars.menuBarItems[@"Cakebrew"] click];
	XCUIElement *aboutItem = self.app.menuItems[@"About Cakebrew"];
	XCTAssertTrue([aboutItem waitForExistenceWithTimeout:10.0], @"the app menu should offer About");
	[aboutItem click];

	NSPredicate *credits = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"DCOAboutWindowController"];
	XCUIElement *creditsView = [[self.app.textViews matchingPredicate:credits] firstMatch];
	BOOL appeared = [creditsView waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the About window should render the credits");

	NSString *shown = (NSString *)creditsView.value;
	XCTAssertFalse([shown containsString:@"Sparkle"],
				   @"Sparkle is not shipped and must not be credited");
	XCTAssertFalse([shown containsString:@"PXSourceList"],
				   @"PXSourceList is not shipped either");
}

// Journey: the app reopens on the sidebar row last used, rather than always on
// Installed. The stored row arrives through the argument domain here, which is
// what -[BPPreferences lastSelectedSidebarRow] reads.
- (void)testReopensOnTheLastUsedSidebarRow
{
	[self launchWithArguments:@[ @"-BPMockBrew", @"-BPLastSelectedSidebarRow", @"12" ]];

	// Row 12 is Doctor, so its view should be showing without any navigation.
	XCTAssertTrue([self.app.staticTexts[@"Homebrew Doctor"] waitForExistenceWithTimeout:30.0],
				  @"the app should reopen on the row the user last selected");
}

// Journey: a stored row that no longer addresses a real destination falls back
// to Installed rather than opening on nothing.
- (void)testAnOutOfRangeStoredRowFallsBackToInstalled
{
	// Row 99 addresses nothing, so the app should land on Installed — which is
	// exactly what the shared launch helper waits for.
	[self launchWithArguments:@[ @"-BPMockBrew", @"-BPLastSelectedSidebarRow", @"99" ]];

	XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:30.0],
				  @"an unusable stored row should fall back to the Installed list");
}

// Journey: uninstalling a cask offers to remove its support files too, and
// uninstalling a formula does not — formulae have no zap stanza.
- (void)testZapCheckboxAppearsForCasksOnly
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	// A cask: the box should be offered.
	[[[sidebar.staticTexts matchingIdentifier:@"Installed"] elementBoundByIndex:1] click];
	XCUIElement *cask = [self formulaCellWithName:@"mockchrome"];
	XCTAssertTrue([cask waitForExistenceWithTimeout:30.0], @"mockchrome should be an installed cask");
	[cask click];

	XCUIElement *uninstall = self.app.buttons[@"Uninstall Formula"];
	XCTAssertTrue([uninstall waitForExistenceWithTimeout:15.0]);
	[uninstall click];

	NSPredicate *zap = [NSPredicate predicateWithFormat:@"title CONTAINS %@", @"zap"];
	XCUIElement *zapBox = [[self.app.checkBoxes matchingPredicate:zap] firstMatch];
	BOOL offered = [zapBox waitForExistenceWithTimeout:15.0];
	if (!offered) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(offered, @"a cask uninstall should offer to remove support files");
	[self dismissConfirmationSheet];

	// A formula: it should not be.
	[[[sidebar.staticTexts matchingIdentifier:@"Installed"] elementBoundByIndex:0] click];
	XCUIElement *formula = [self formulaCellWithName:@"mockwget"];
	XCTAssertTrue([formula waitForExistenceWithTimeout:30.0]);
	[formula click];

	XCUIElement *uninstallFormula = self.app.buttons[@"Uninstall Formula"];
	XCTAssertTrue([uninstallFormula waitForExistenceWithTimeout:15.0]);
	[uninstallFormula click];
	XCTAssertTrue([self.app.buttons[@"Yes"] waitForExistenceWithTimeout:15.0], @"the confirmation should appear");
	XCTAssertFalse([[self.app.checkBoxes matchingPredicate:zap] firstMatch].exists,
				   @"formulae have no zap stanza, so the box must not be offered");
	[self dismissConfirmationSheet];
}

// Journey: View ▸ Show/Hide Sidebar collapses the sidebar and restores it.
// There was no way to hide the sidebar at all before — no menu item, no
// shortcut, no toolbar button — despite the window using a collapsible
// NSSplitViewItem.
- (void)testShowHideSidebarCollapsesAndRestoresTheSidebar
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];
	// Width, not isHittable: the CI runner's window is never key, so hit
	// testing reports false there even while the sidebar is plainly visible.
	XCTAssertGreaterThan(sidebar.frame.size.width, 1.0, @"the sidebar starts visible");

	// AppKit retitles the item to "Hide Sidebar" or "Show Sidebar" to match the
	// current state, so match on the noun rather than a fixed title.
	NSPredicate *sidebarItem = [NSPredicate predicateWithFormat:@"title ENDSWITH %@", @"Sidebar"];
	[self.app.menuBars.menuBarItems[@"View"] click];
	XCUIElement *toggleItem = [[self.app.menuItems matchingPredicate:sidebarItem] firstMatch];
	XCTAssertTrue([toggleItem waitForExistenceWithTimeout:10.0], @"View should offer a sidebar toggle");
	[toggleItem click];

	BOOL didCollapse = [self waitForSidebar:sidebar collapsed:YES timeout:15.0];
	if (!didCollapse) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(didCollapse, @"the sidebar should collapse");

	// And back again — it is a toggle, not a one-way hide.
	[self.app.menuBars.menuBarItems[@"View"] click];
	[[[self.app.menuItems matchingPredicate:sidebarItem] firstMatch] click];

	XCTAssertTrue([self waitForSidebar:sidebar collapsed:NO timeout:15.0],
				  @"the sidebar should come back");
}

- (void)testSettingsWindowOpensFromMenu
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	[self.app.menuBars.menuBarItems[@"Cakebrew"] click];
	// AppKit auto-renames "Preferences…" to "Settings…" (macOS 13+), so the
	// rendered item carries the new title on every supported OS.
	XCUIElement *prefsItem = self.app.menuItems[@"Settings…"];
	XCTAssertTrue([prefsItem waitForExistenceWithTimeout:10.0], @"the app menu should show Settings…");
	[prefsItem click];

	XCUIElement *prefsWindow = self.app.windows[@"Settings"];
	BOOL appeared = [prefsWindow waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the Preferences window should open");

	XCTAssertTrue(prefsWindow.checkBoxes[@"Check for outdated packages in the background"].exists,
				  @"the background-check toggle should be present");
	XCTAssertTrue(prefsWindow.checkBoxes[@"Include auto-updating apps in outdated casks"].exists,
				  @"the greedy-casks toggle should be present");

	// Helper status row. Unsandboxed (the shipping configuration), so it must
	// say the helper isn't needed rather than nagging for approval.
	XCTAssertTrue(prefsWindow.staticTexts[@"Homebrew access:"].exists,
				  @"the helper status row should be present");
	NSPredicate *notRequired = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"Not required"];
	XCTAssertTrue([[prefsWindow.staticTexts matchingPredicate:notRequired] firstMatch].exists,
				  @"an unsandboxed build reports the helper as not required");

	[prefsWindow.buttons[XCUIIdentifierCloseWindow] click];
}

// Journey: the Services tool lists brew services with status and offers
// the start/stop/restart controls.
- (void)testServicesToolListsServicesWithControls
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	[self.sidebar.staticTexts[@"Services"] click];

	XCTAssertTrue([self.app.staticTexts[@"Homebrew Services"] waitForExistenceWithTimeout:15.0],
				  @"selecting Services should show the Services view");

	XCUIElement *postgres = [self formulaCellWithName:@"mockpostgres"];
	BOOL appeared = [postgres waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the services table should list mockpostgres");
	XCTAssertTrue([self formulaCellWithName:@"mockredis"].exists, @"the services table should list mockredis");

	XCTAssertTrue(self.app.buttons[@"Start"].exists, @"a Start button should be present");
	XCTAssertTrue(self.app.buttons[@"Stop"].exists, @"a Stop button should be present");
	XCTAssertTrue(self.app.buttons[@"Restart"].exists, @"a Restart button should be present");

	// Selecting the running service enables Stop.
	[postgres click];
	XCTAssertTrue([self.app.buttons[@"Stop"] waitForExistenceWithTimeout:5.0]);
	XCTAssertTrue(self.app.buttons[@"Stop"].isEnabled, @"Stop should enable for a started service");
}

// Journey: selecting a cask shows the detail pane populated from
// `brew info --cask` (description parsed from the cask output shape).
- (void)testSelectingCaskShowsCaskInfoInDetailPane
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *sidebar = self.sidebar;
	XCUIElementQuery *installedRows = [sidebar.staticTexts matchingIdentifier:@"Installed"];
	XCTAssertTrue([installedRows.firstMatch waitForExistenceWithTimeout:30.0], @"sidebar should load");
	[[installedRows elementBoundByIndex:1] click];

	XCUIElement *chrome = [self formulaCellWithName:@"mockchrome"];
	XCTAssertTrue([chrome waitForExistenceWithTimeout:15.0], @"mockchrome should be listed");
	[chrome click];

	// The mock's cask-info fixture description, parsed through the cask branch.
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value CONTAINS %@",
							  @"A mock cask used for Cakebrew UI tests."];
	XCUIElement *description = [[self.app.staticTexts matchingPredicate:predicate] firstMatch];
	BOOL appeared = [description waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the detail pane should show the cask description");
}

// Journey: the All Casks section lists the catalog; a not-installed cask
// offers Install with confirmation (dispatches to `install --cask`).
- (void)testAllCasksOffersInstallWithConfirmation
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	[self.sidebar.staticTexts[@"All Casks"] click];

	XCUIElement *firefox = [self formulaCellWithName:@"mockfirefox"];
	BOOL appeared = [firefox waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"mockfirefox should be listed under All Casks");
	[firefox click];

	XCUIElement *installButton = self.app.buttons[@"Install Formula"];
	XCTAssertTrue([installButton waitForExistenceWithTimeout:15.0],
				  @"selecting a not-installed cask should offer Install in the toolbar");
	[installButton click];

	XCUIElement *yesButton = self.app.buttons[@"Yes"];
	XCTAssertTrue([yesButton waitForExistenceWithTimeout:15.0],
				  @"clicking Install on a cask should present a Yes/Cancel confirmation");

	// Cancel so the test doesn't proceed into the operation.
	[self dismissConfirmationSheet];
}

// Journey: selecting an installed cask offers Uninstall, which asks for
// confirmation (the operation pipeline dispatches to `uninstall --cask`).
- (void)testCaskOffersUninstallWithConfirmation
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *sidebar = self.sidebar;
	XCUIElementQuery *installedRows = [sidebar.staticTexts matchingIdentifier:@"Installed"];
	XCTAssertTrue([installedRows.firstMatch waitForExistenceWithTimeout:30.0], @"sidebar should load");
	[[installedRows elementBoundByIndex:1] click];

	XCUIElement *chrome = [self formulaCellWithName:@"mockchrome"];
	XCTAssertTrue([chrome waitForExistenceWithTimeout:15.0], @"mockchrome should be listed");
	[chrome click];

	XCUIElement *uninstallButton = self.app.buttons[@"Uninstall Formula"];
	BOOL appeared = [uninstallButton waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"selecting a cask should offer Uninstall in the toolbar");
	[uninstallButton click];

	XCUIElement *yesButton = self.app.buttons[@"Yes"];
	XCTAssertTrue([yesButton waitForExistenceWithTimeout:15.0],
				  @"clicking Uninstall on a cask should present a Yes/Cancel confirmation");

	// Cancel so the test doesn't proceed into the operation.
	[self dismissConfirmationSheet];
}

// Journey: clicking Uninstall on an installed formula asks for confirmation.
- (void)testUninstallPresentsConfirmationDialog
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *wget = [self formulaCellWithName:@"mockwget"];
	XCTAssertTrue([wget waitForExistenceWithTimeout:30.0], @"mockwget should be in the Installed list");
	[wget click];

	XCUIElement *uninstallButton = self.app.buttons[@"Uninstall Formula"];
	XCTAssertTrue([uninstallButton waitForExistenceWithTimeout:15.0], @"Uninstall should be offered");
	[uninstallButton click];

	// uninstallFormula: presents a Yes / Cancel confirmation sheet.
	XCUIElement *yesButton = self.app.buttons[@"Yes"];
	BOOL confirmationAppeared = [yesButton waitForExistenceWithTimeout:15.0];
	if (!confirmationAppeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(confirmationAppeared, @"clicking Uninstall should present a Yes/Cancel confirmation");

	// Cancel so the test doesn't proceed into the uninstall operation.
	[self dismissConfirmationSheet];
}

// Journey: selecting an outdated formula offers Update in the toolbar.
- (void)testOutdatedFormulaOffersUpdate
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	// Two "Outdated" rows exist (Formulae + Casks); the formulae one is first.
	[[[sidebar.staticTexts matchingIdentifier:@"Outdated"] elementBoundByIndex:0] click];
	XCUIElement *git = [self formulaCellWithName:@"mockgit"];
	XCTAssertTrue([git waitForExistenceWithTimeout:30.0], @"mockgit should be in the Outdated list");
	[git click];

	XCUIElement *updateButton = self.app.buttons[@"Update Formula"];
	BOOL appeared = [updateButton waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"selecting an outdated formula should offer Update in the toolbar");
}

// Journey: clicking Update on an outdated formula asks for confirmation.
- (void)testUpgradePresentsConfirmationDialog
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	// Two "Outdated" rows exist (Formulae + Casks); the formulae one is first.
	[[[sidebar.staticTexts matchingIdentifier:@"Outdated"] elementBoundByIndex:0] click];
	XCUIElement *git = [self formulaCellWithName:@"mockgit"];
	XCTAssertTrue([git waitForExistenceWithTimeout:30.0], @"mockgit should be in the Outdated list");
	[git click];

	XCUIElement *updateButton = self.app.buttons[@"Update Formula"];
	XCTAssertTrue([updateButton waitForExistenceWithTimeout:15.0], @"Update should be offered");
	[updateButton click];

	// upgradeSelectedFormulae: presents a Yes / Cancel confirmation sheet.
	XCUIElement *yesButton = self.app.buttons[@"Yes"];
	BOOL confirmationAppeared = [yesButton waitForExistenceWithTimeout:15.0];
	if (!confirmationAppeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(confirmationAppeared, @"clicking Update should present a Yes/Cancel confirmation");

	// Cancel so the test doesn't proceed into the upgrade operation.
	[self dismissConfirmationSheet];
}

// Journey: running Doctor streams its report into the Doctor view.
- (void)testRunningDoctorShowsOutput
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	[sidebar.staticTexts[@"Doctor"] click];
	XCTAssertTrue([self.app.staticTexts[@"Homebrew Doctor"] waitForExistenceWithTimeout:15.0],
				  @"the Doctor view should appear");

	XCUIElement *runButton = self.app.buttons[@"Run Doctor"];
	XCTAssertTrue([runButton waitForExistenceWithTimeout:15.0], @"the Run Doctor button should exist");
	[runButton click];

	// The mock streams three chunks. Requiring the first marker *and* the last
	// in the same text view is the regression guard: the Doctor view used to
	// replace its whole document per chunk, so only the final chunk survived.
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value CONTAINS %@ AND value CONTAINS %@",
							  @"MOCK_DOCTOR_OK", @"MOCK_DOCTOR_DONE"];
	XCUIElement *output = [[self.app.textViews matchingPredicate:predicate] firstMatch];
	BOOL appeared = [output waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"Doctor should accumulate every chunk, not just the last one");
}

// Journey: the toolbar's Update Homebrew button switches to the Update view and
// streams the update output into it. The toolbar button (scoped via toolbars)
// is used to avoid the name clash with the Update view's own button.
- (void)testRunningUpdateHomebrewShowsOutput
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *updateButton = [self.app.toolbars.buttons[@"Update Homebrew"] firstMatch];
	XCTAssertTrue([updateButton waitForExistenceWithTimeout:15.0], @"the toolbar Update Homebrew button should exist");
	[updateButton click];

	XCTAssertTrue([self.app.staticTexts[@"Homebrew Updater"] waitForExistenceWithTimeout:15.0],
				  @"clicking Update Homebrew should show the Update view");

	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"MOCK_UPDATE_OK"];
	XCUIElement *output = [[self.app.textViews matchingPredicate:predicate] firstMatch];
	BOOL appeared = [output waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"running Update Homebrew should stream its output into the Update view");
}

#pragma mark - Repository (tap/untap) journeys

// Journey: with no repository selected, Tap offers a repo-name input dialog.
- (void)testTapPresentsInputDialog
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	[sidebar.staticTexts[@"Repositories"] click];

	XCUIElement *tapButton = self.app.buttons[@"Tap Repository"];
	XCTAssertTrue([tapButton waitForExistenceWithTimeout:15.0], @"Tap Repository should be offered");
	[tapButton click];

	// tapRepository: presents an OK/Cancel input dialog.
	XCUIElement *okButton = self.app.buttons[@"OK"];
	BOOL appeared = [okButton waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"Tap should present an input dialog with OK/Cancel");

	[self dismissConfirmationSheet];
}

// Journey: selecting a tapped repository and choosing Untap asks for confirmation.
- (void)testUntapPresentsConfirmationDialog
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];

	[sidebar.staticTexts[@"Repositories"] click];

	XCUIElement *repo = [self formulaCellWithName:@"homebrew/core"];
	BOOL repoListed = [repo waitForExistenceWithTimeout:30.0];
	if (!repoListed) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(repoListed, @"a tapped repository should be listed");
	[repo click];

	XCUIElement *untapButton = self.app.buttons[@"Untap Repository"];
	XCTAssertTrue([untapButton waitForExistenceWithTimeout:15.0], @"Untap Repository should be offered");
	[untapButton click];

	// untapRepository: presents an OK/Cancel confirmation.
	XCUIElement *okButton = self.app.buttons[@"OK"];
	BOOL appeared = [okButton waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"Untap should present a confirmation with OK/Cancel");

	[self dismissConfirmationSheet];
}

#pragma mark - Search journey

// Journey: the toolbar provides a search field.
//
// The actual type-and-filter behaviour can't be driven here: the headless CI
// session never makes the app window key, so no text field can take keyboard
// focus (XCUITest reports "Neither element nor any descendant has keyboard
// focus"). The search *filtering* logic is covered deterministically by a unit
// test instead (BPHomebrewManagerTests testUpdateSearchFiltersAllFormulaeByName).
- (void)testSearchFieldIsAvailable
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:30.0],
				  @"the mock data should load");

	XCUIElement *searchField = self.app.searchFields.firstMatch;
	BOOL exists = [searchField waitForExistenceWithTimeout:15.0];
	if (!exists) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(exists, @"the toolbar should provide a search field");
}

#pragma mark - Formula info journey

// Journey: More Information shows the selected formula's details in a popover.
- (void)testMoreInformationShowsFormulaInfoPopover
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *wget = [self formulaCellWithName:@"mockwget"];
	XCTAssertTrue([wget waitForExistenceWithTimeout:30.0], @"mockwget should be in the Installed list");
	[wget click];

	XCUIElement *infoButton = self.app.buttons[@"More Information"];
	XCTAssertTrue([infoButton waitForExistenceWithTimeout:15.0], @"More Information should be offered");
	[infoButton click];

	// The popover shows the formula's info (served by the mock interface).
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"A mock formula"];
	XCUIElement *infoText = [[self.app.textViews matchingPredicate:predicate] firstMatch];
	BOOL appeared = [infoText waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"More Information should show the formula info in a popover");
}

#pragma mark - Tools journeys

// Journey: Tools > Brew Cleanup runs cleanup and streams its output.
- (void)testCleanupStreamsOutput
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:30.0],
				  @"the mock data should load");

	[self.app.menuBars.menuBarItems[@"Tools"] click];
	XCUIElement *cleanupItem = self.app.menuItems[@"Brew Cleanup…"];
	XCTAssertTrue([cleanupItem waitForExistenceWithTimeout:10.0], @"Tools > Brew Cleanup should exist");
	[cleanupItem click];

	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"MOCK_CLEANUP_OK"];
	XCUIElement *output = [[self.app.textViews matchingPredicate:predicate] firstMatch];
	BOOL appeared = [output waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"running Cleanup should stream its output");
}

// Journey: the Tools menu exposes the Import / Export Brewfile actions.
//
// The full flow opens a system file panel (a separate process) and needs a
// typed filename — neither is drivable under the CI key-window limit — so this
// verifies the menu entry points are present rather than the whole operation.
- (void)testToolsMenuExposesImportAndExport
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:30.0],
				  @"the mock data should load");

	[self.app.menuBars.menuBarItems[@"Tools"] click];

	BOOL exportPresent = [self.app.menuItems[@"Export Brew Installation…"] waitForExistenceWithTimeout:10.0];
	BOOL importPresent = self.app.menuItems[@"Import Brew Installation…"].exists;
	if (!exportPresent || !importPresent) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(exportPresent, @"Tools should offer Export Brew Installation");
	XCTAssertTrue(importPresent, @"Tools should offer Import Brew Installation");
}

@end
