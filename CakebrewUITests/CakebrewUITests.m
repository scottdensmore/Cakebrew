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
	self.app.launchArguments = arguments;
	[self.app launch];
	XCTAssertTrue([self.app.windows.firstMatch waitForExistenceWithTimeout:30.0],
				  @"the main window should appear after launch");
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
- (void)testSidebarShowsAllNavigationItems
{
	[self launchWithArguments:@[]];
	XCUIElement *sidebar = [self sidebar];
	NSArray<NSString *> *items = @[ @"Installed", @"Outdated", @"All Formulae",
									@"Leaves", @"Repositories", @"Doctor", @"Update" ];
	for (NSString *item in items) {
		XCTAssertTrue([sidebar.staticTexts[item] waitForExistenceWithTimeout:15.0],
					  @"the sidebar should show the %@ item", item);
	}
}

// Journey: selecting a Tools item switches the content to that tool's view.
- (void)testNavigatingToToolViewsFromSidebar
{
	[self launchWithArguments:@[]];
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
	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value == %@", name];
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
	XCTAssertTrue([htop waitForExistenceWithTimeout:30.0], @"mockhtop should be listed under All Formulae");
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

	[sidebar.staticTexts[@"Outdated"] click];
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

	[sidebar.staticTexts[@"Outdated"] click];
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

	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"MOCK_DOCTOR_OK"];
	XCUIElement *output = [[self.app.textViews matchingPredicate:predicate] firstMatch];
	BOOL appeared = [output waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"running Doctor should stream its report into the Doctor view");
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

@end
