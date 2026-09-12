//
//  CakebrewUITests.m
//  CakebrewUITests
//
//  End-to-end UI tests that drive the real app via XCUITest.
//

#import <XCTest/XCTest.h>

@interface CakebrewUITests : XCTestCase
@property (strong) XCUIApplication *app;
@property (strong) NSURL *brewfileFixtureDirectory;
@end

@implementation CakebrewUITests

- (void)openAutoremoveWithArguments:(NSArray *)arguments
{
	[self launchWithArguments:[@[@"-BPMockBrew"] arrayByAddingObjectsFromArray:arguments]];
	[self.app.menuBars.menuBarItems[@"Tools"] click];
	[self.app.menuItems[@"Remove Unused Dependencies…"] click];
	XCTAssertTrue([self.app.sheets.firstMatch.textViews[@"autoremove.output"] waitForExistenceWithTimeout:10]);
}
- (void)testAutoremoveReviewedRemovalStreamsAndFinishes
{
	[self openAutoremoveWithArguments:@[]];
	XCUIElement *remove = self.app.sheets.firstMatch.buttons[@"autoremove.remove"];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] evaluatedWithObject:remove handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertTrue([self.app.textViews[@"autoremove.output"].value containsString:@"mockunused"]);
	[remove click];
	XCUIElement *status = self.app.staticTexts[@"autoremove.status"];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'were removed'"] evaluatedWithObject:status handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertTrue([self.app.textViews[@"autoremove.output"].value containsString:@"MOCK_AUTOREMOVE_OK"]);
	XCTAssertTrue(self.app.sheets.firstMatch.buttons[@"autoremove.cancel"].enabled);
}
- (void)testAutoremoveReviewCancellationDoesNotRunRemoval
{
	[self openAutoremoveWithArguments:@[]];
	XCUIElement *remove = self.app.sheets.firstMatch.buttons[@"autoremove.remove"];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] evaluatedWithObject:remove handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertFalse([self.app.textViews[@"autoremove.output"].value containsString:@"MOCK_AUTOREMOVE_STARTED"]);
	[self.app.sheets.firstMatch.buttons[@"autoremove.cancel"] click];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"exists == NO"] evaluatedWithObject:self.app.sheets.firstMatch handler:nil];
	[self waitForExpectationsWithTimeout:5 handler:nil];
}
- (void)testAutoremoveIncompleteRefreshRemainsVisibleAfterRemoval
{
	[self openAutoremoveWithArguments:@[@"-BPMockFailedAutoremoveRefresh"]];
	XCUIElement *remove = self.app.sheets.firstMatch.buttons[@"autoremove.remove"];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] evaluatedWithObject:remove handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	[remove click];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'could not be refreshed'"] evaluatedWithObject:self.app.staticTexts[@"autoremove.status"] handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertTrue([self.app.textViews[@"autoremove.output"].value containsString:@"MOCK_AUTOREMOVE_OK"]);
	XCTAssertTrue(self.app.sheets.firstMatch.buttons[@"autoremove.cancel"].enabled);
}
- (void)testAutoremoveEmptyPreviewDoesNotEnableRemoval
{
	[self openAutoremoveWithArguments:@[@"-BPMockEmptyAutoremove"]];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'No unused'"] evaluatedWithObject:self.app.staticTexts[@"autoremove.status"] handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertFalse(self.app.sheets.firstMatch.buttons[@"autoremove.remove"].enabled);
}
- (void)testAutoremoveMalformedPreviewDoesNotEnableRemoval
{
	[self openAutoremoveWithArguments:@[@"-BPMockInvalidAutoremove"]];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'could not'"] evaluatedWithObject:self.app.staticTexts[@"autoremove.status"] handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertFalse(self.app.sheets.firstMatch.buttons[@"autoremove.remove"].enabled);
	XCTAssertTrue([self.app.textViews[@"autoremove.output"].value containsString:@"MOCK_UNRECOGNIZED"]);
}
- (void)testAutoremoveActiveCancellationReportsPartialChanges
{
	[self openAutoremoveWithArguments:@[@"-BPMockSlowAutoremove"]];
	XCUIElement *remove = self.app.sheets.firstMatch.buttons[@"autoremove.remove"];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] evaluatedWithObject:remove handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	[remove click];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'MOCK_AUTOREMOVE_STARTED'"] evaluatedWithObject:self.app.textViews[@"autoremove.output"] handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	[self.app.sheets.firstMatch.buttons[@"autoremove.cancel"] click];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'partially removed'"] evaluatedWithObject:self.app.staticTexts[@"autoremove.status"] handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertFalse([self.app.textViews[@"autoremove.output"].value containsString:@"MOCK_AUTOREMOVE_OK"]);
}

- (void)testAutoremoveChangedPreviewCannotRunRemoval
{
	[self openAutoremoveWithArguments:@[@"-BPMockChangedAutoremove"]];
	XCUIElement *remove = self.app.sheets.firstMatch.buttons[@"autoremove.remove"];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] evaluatedWithObject:remove handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	[remove click];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'list changed'"] evaluatedWithObject:self.app.staticTexts[@"autoremove.status"] handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertFalse([self.app.textViews[@"autoremove.output"].value containsString:@"MOCK_AUTOREMOVE_STARTED"]);
}
- (void)testAutoremoveFailureKeepsDiagnosticsVisible
{
	[self openAutoremoveWithArguments:@[@"-BPMockFailedAutoremove"]];
	XCUIElement *remove = self.app.sheets.firstMatch.buttons[@"autoremove.remove"];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] evaluatedWithObject:remove handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	[remove click];
	[self expectationForPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'Removal failed'"] evaluatedWithObject:self.app.staticTexts[@"autoremove.status"] handler:nil];
	[self waitForExpectationsWithTimeout:10 handler:nil];
	XCTAssertTrue([self.app.textViews[@"autoremove.output"].value containsString:@"MOCK_AUTOREMOVE_FAILED"]);
	XCTAssertFalse([self.app.textViews[@"autoremove.output"].value containsString:@"MOCK_AUTOREMOVE_OK"]);
}

- (void)setUp
{
	[super setUp];
	self.continueAfterFailure = NO;
	self.app = [[XCUIApplication alloc] init];
}

- (void)tearDown
{
	[self.app terminate];
 if (self.brewfileFixtureDirectory) [[NSFileManager defaultManager] removeItemAtURL:self.brewfileFixtureDirectory error:NULL];
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
/// Addresses a sidebar row by its accessibility identifier. The rows carry
/// stable, unlocalized identifiers precisely so journeys stop disambiguating
/// duplicate titles by index — "Installed" and "Outdated" each appear under
/// both Formulae and Casks.
- (XCUIElement *)sidebarRow:(NSString *)identifier
{
	return [self sidebar].staticTexts[identifier];
}

- (void)dismissConfirmationSheet
{
	[self.app typeKey:XCUIKeyboardKeyEscape modifierFlags:XCUIKeyModifierNone];
}

#pragma mark - Launch / chrome

// Mouse journeys are valid on headless CI; keyboard routing is exercised by
// synthetic NSEvents in BPFormulaeTableActionTests and checked locally on macOS.
- (void)testDoubleClickInstalledFormulaShowsInfoWithoutUninstalling
{
	[self launchWithArguments:@[@"-BPMockBrew"]];
	[[self formulaCellWithName:@"mockwget"] doubleClick];
	XCUIElement *info = [[[self.app descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:@"formula.information.text"] matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@ OR value CONTAINS %@", @"A mock formula", @"A mock formula"]].firstMatch;
	BOOL appeared = [info waitForExistenceWithTimeout:15];
	if (!appeared) NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	XCTAssertTrue(appeared);
	XCTAssertFalse(self.app.sheets.firstMatch.exists, @"Installed primary action is information, not uninstall");
}

- (void)testDoubleClickInstalledCaskShowsInfoWithoutUninstalling
{
	[self launchWithArguments:@[@"-BPMockBrew"]];
	[[self sidebarRow:@"sidebar.casks.installed"] click];
	XCUIElement *cask = [self formulaCellWithName:@"mockchrome"];
	XCTAssertTrue([cask waitForExistenceWithTimeout:15]);
	[cask doubleClick];
	XCUIElement *info = [[[self.app descendantsMatchingType:XCUIElementTypeAny] matchingIdentifier:@"formula.information.text"] matchingPredicate:[NSPredicate predicateWithFormat:@"label CONTAINS %@ OR value CONTAINS %@", @"A mock cask", @"A mock cask"]].firstMatch;
	BOOL appeared = [info waitForExistenceWithTimeout:15];
	if (!appeared) NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	XCTAssertTrue(appeared);
	XCTAssertFalse(self.app.sheets.firstMatch.exists);
}

- (void)testDoubleClickAvailableFormulaUsesInstallConfirmationAndCancel
{
	[self launchWithArguments:@[@"-BPMockBrew"]];
	[[self sidebarRow:@"sidebar.formulae.all"] click];
	XCUIElement *formula = [self formulaCellWithName:@"mockhtop"];
	XCTAssertTrue([formula waitForExistenceWithTimeout:15]);
	[formula doubleClick];
	XCUIElement *sheet = self.app.sheets.firstMatch;
	BOOL appeared = [sheet.buttons[@"Yes"] waitForExistenceWithTimeout:15];
	if (!appeared) NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	XCTAssertTrue(appeared);
	XCUIElement *message = [sheet.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS %@", @"mockhtop"]].firstMatch;
	XCTAssertTrue(message.exists);
	[sheet.buttons[@"Cancel"] click];
	XCTAssertTrue([sheet waitForNonExistenceWithTimeout:10]);
	XCTAssertTrue(formula.exists);
	XCTAssertTrue(self.app.buttons[@"Install Formula"].exists, @"Cancel leaves the selected package uninstalled");
}

- (void)testDoubleClickOutdatedFormulaAndCaskUseUpgradeConfirmation
{
	[self launchWithArguments:@[@"-BPMockBrew"]];
	NSArray *rows = @[@"sidebar.formulae.outdated", @"sidebar.casks.outdated"];
	NSArray *names = @[@"mockgit", @"mockchrome"];
	for (NSUInteger index = 0; index < rows.count; index++) {
		[[self sidebarRow:rows[index]] click];
		XCUIElement *formula = [self formulaCellWithName:names[index]];
		XCTAssertTrue([formula waitForExistenceWithTimeout:15]);
		[formula doubleClick];
		XCUIElement *sheet = self.app.sheets.firstMatch;
		BOOL appeared = [sheet.buttons[@"Yes"] waitForExistenceWithTimeout:15];
		if (!appeared) NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
		XCTAssertTrue(appeared);
		XCTAssertTrue(sheet.staticTexts[@"Updating Formulae"].exists);
		XCUIElement *message = [sheet.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS %@", names[index]]].firstMatch;
		XCTAssertTrue(message.exists);
		[sheet.buttons[@"Cancel"] click];
		XCTAssertTrue([sheet waitForNonExistenceWithTimeout:10]);
		XCTAssertTrue(formula.exists);
	}
}

- (void)testConfirmedSelectedFormulaAndCaskUpgradesComplete
{
	[self launchWithArguments:@[@"-BPMockBrew"]];
	NSArray *rows = @[@"sidebar.formulae.outdated", @"sidebar.casks.outdated"];
	NSArray *names = @[@"mockgit", @"mockchrome"];
	NSArray *commands = @[@"MOCK_UPGRADE_ARGUMENTS: upgrade --formula mockgit",
						  @"MOCK_UPGRADE_ARGUMENTS: upgrade --cask mockchrome"];
	for (NSUInteger index = 0; index < rows.count; index++) {
		[[self sidebarRow:rows[index]] click];
		XCUIElement *formula = [self formulaCellWithName:names[index]];
		XCTAssertTrue([formula waitForExistenceWithTimeout:15]);
		[formula doubleClick];
		XCUIElement *yes = self.app.sheets.firstMatch.buttons[@"Yes"];
		XCTAssertTrue([yes waitForExistenceWithTimeout:15]);
		[yes click];

		XCUIElement *sheet = self.app.sheets.firstMatch;
		NSPredicate *transcript = [NSPredicate predicateWithFormat:@"value CONTAINS %@ AND value CONTAINS %@",
								  @"MOCK_UPGRADE_OK", commands[index]];
		XCUIElement *output = [sheet.textViews matchingPredicate:transcript].firstMatch;
		BOOL appeared = [output waitForExistenceWithTimeout:15];
		if (!appeared) NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
		XCTAssertTrue(appeared, @"Confirmed selection must execute in its own namespace");
		XCUIElement *ok = sheet.buttons[@"OK"];
		XCTAssertTrue([ok waitForExistenceWithTimeout:15]);
		XCTNSPredicateExpectation *finished = [[XCTNSPredicateExpectation alloc]
			initWithPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] object:ok];
		XCTAssertEqual([XCTWaiter waitForExpectations:@[finished] timeout:15], XCTWaiterResultCompleted);
		XCTAssertFalse(sheet.buttons[@"Cancel"].enabled);
		[ok click];
		XCTAssertTrue([sheet waitForNonExistenceWithTimeout:10]);
		XCTAssertTrue(formula.exists, @"Mock upgrade leaves the selected fixture available");
	}
	// A new confirmation after the final dismissal proves cleanup released
	// the busy guard, rather than merely hiding the operation window.
	[[self sidebarRow:@"sidebar.formulae.outdated"] click];
	[[self formulaCellWithName:@"mockgit"] doubleClick];
	XCUIElement *nextSheet = self.app.sheets.firstMatch;
	BOOL nextActionReady = [nextSheet.buttons[@"Yes"] waitForExistenceWithTimeout:15];
	if (!nextActionReady) NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	XCTAssertTrue(nextActionReady, @"Dismissal must permit another upgrade action");
	[nextSheet.buttons[@"Cancel"] click];
	XCTAssertTrue([nextSheet waitForNonExistenceWithTimeout:10]);
}

- (void)testDoubleClickAvailableCaskUsesInstallConfirmationAndCancel
{
	[self launchWithArguments:@[@"-BPMockBrew"]];
	[[self sidebarRow:@"sidebar.casks.all"] click];
	XCUIElement *cask = [self formulaCellWithName:@"mockfirefox"];
	XCTAssertTrue([cask waitForExistenceWithTimeout:15]);
	[cask doubleClick];
	XCUIElement *sheet = self.app.sheets.firstMatch;
	BOOL appeared = [sheet.buttons[@"Yes"] waitForExistenceWithTimeout:15];
	if (!appeared) NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	XCTAssertTrue(appeared);
	XCUIElement *message = [sheet.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS %@", @"mockfirefox"]].firstMatch;
	XCTAssertTrue(message.exists);
	[sheet.buttons[@"Cancel"] click];
	XCTAssertTrue([sheet waitForNonExistenceWithTimeout:10]);
	XCTAssertTrue(cask.exists);
	XCTAssertTrue(self.app.buttons[@"Install Formula"].exists);
}

- (void)testDoubleClickEmptyTableSpaceDoesNotActOnSelectedFormula
{
	[self launchWithArguments:@[@"-BPMockBrew"]];
	[[self sidebarRow:@"sidebar.formulae.all"] click];
	XCUIElement *formula = [self formulaCellWithName:@"mockhtop"];
	XCTAssertTrue([formula waitForExistenceWithTimeout:15]);
	[formula click];
	XCUIElement *table = self.app.tables.firstMatch;
	XCTAssertTrue(table.exists);
	CGFloat rowsBottom = 0;
	NSArray<XCUIElement *> *tableRows = [table descendantsMatchingType:XCUIElementTypeTableRow].allElementsBoundByIndex;
	XCTAssertGreaterThan(tableRows.count, 0u, @"Validate that the row geometry probe found the rendered rows");
	for (XCUIElement *row in tableRows) rowsBottom = MAX(rowsBottom, CGRectGetMaxY(row.frame));
	CGFloat y = CGRectGetMaxY(table.frame) - 8;
	XCTAssertGreaterThan(y, rowsBottom, @"The click must really be below every row");
	XCUICoordinate *point = [[table coordinateWithNormalizedOffset:CGVectorMake(0, 0)] coordinateWithOffset:CGVectorMake(20, y - CGRectGetMinY(table.frame))];
	[point doubleClick];
	XCTAssertFalse([self.app.sheets.firstMatch waitForExistenceWithTimeout:2]);
}

- (void)openBrewfileReviewWithContents:(NSString *)contents extraArguments:(NSArray *)arguments
{
 self.brewfileFixtureDirectory = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:NSUUID.UUID.UUIDString];
 XCTAssertTrue([[NSFileManager defaultManager] createDirectoryAtURL:self.brewfileFixtureDirectory withIntermediateDirectories:NO attributes:nil error:NULL]);
 NSURL *file = [self.brewfileFixtureDirectory URLByAppendingPathComponent:@"Brewfile"];
 XCTAssertTrue([contents writeToURL:file atomically:YES encoding:NSUTF8StringEncoding error:NULL]);
 [self launchWithArguments:[@[@"-BPMockBrew", @"-BPMockBrewfileURL", file.path] arrayByAddingObjectsFromArray:arguments]];
 [self.app.menuBars.menuBarItems[@"Brewfile Test"] click];
 [self.app.menuItems[@"Review Mock Brewfile"] click];
 XCTAssertTrue([self.app.sheets.firstMatch.buttons[@"brewfile.review.cancel"] waitForExistenceWithTimeout:5]);
}

- (void)testBrewfileReviewShowsGroupedStatusesAndCancelRunsNothing
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'\ncask 'missingapp'\ntap 'owner/tap'\nmas 'App', id: 123\nvscode 'pub.ext'" extraArguments:@[]];
 NSString *review = self.app.sheets.firstMatch.textViews[@"brewfile.review.entries"].value;
 XCTAssertTrue([review containsString:@"mockwget — Installed"]);
 XCTAssertTrue([review containsString:@"missingapp — Missing"]);
 XCTAssertTrue([review containsString:@"Mac App Store"]);
 XCTAssertTrue([review containsString:@"Not checked"]);
 [self.app.sheets.firstMatch.buttons[@"brewfile.review.cancel"] click];
 XCTAssertFalse(self.app.textViews[@"brewfile.import.output"].exists);
}

- (void)testBrewfileReviewBlocksUnsupportedFiles
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'\nsystem('unsafe')" extraArguments:@[]];
 XCTAssertFalse(self.app.sheets.firstMatch.buttons[@"brewfile.review.install"].enabled);
 XCTAssertTrue([self.app.sheets.firstMatch.textViews[@"brewfile.review.entries"].value containsString:@"Line 2"]);
 [self.app.sheets.firstMatch.buttons[@"brewfile.review.cancel"] click];
}

- (void)testBrewfileReviewBlocksEmptyFiles
{
 [self openBrewfileReviewWithContents:@"# no direct entries\n" extraArguments:@[]];
 XCTAssertFalse(self.app.sheets.firstMatch.buttons[@"brewfile.review.install"].enabled);
 XCTAssertTrue([self.app.sheets.firstMatch.textViews[@"brewfile.review.entries"].value containsString:@"No supported package entries"]);
 [self.app.sheets.firstMatch.buttons[@"brewfile.review.cancel"] click];
}

- (void)testBrewfileReviewConfirmedImportFinishes
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'\ncask 'mockchrome'" extraArguments:@[]];
 [self.app.sheets.firstMatch.buttons[@"brewfile.review.install"] click];
 XCUIElement *status = self.app.staticTexts[@"brewfile.import.status"];
 XCTAssertTrue([status waitForExistenceWithTimeout:5]);
 NSPredicate *finished = [NSPredicate predicateWithFormat:@"value == %@", @"Import finished."];
 [self expectationForPredicate:finished evaluatedWithObject:status handler:nil];
 [self waitForExpectationsWithTimeout:10 handler:nil];
 XCTAssertTrue([self.app.textViews[@"brewfile.import.output"].value containsString:@"MOCK_IMPORT_OK"]);
 [self.app.sheets.firstMatch.buttons[@"brewfile.import.action"] click];
}

- (void)testBrewfileImportCanBeCancelledWhileStreaming
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'" extraArguments:@[@"-BPMockHoldBrewfileImportUntilCancelled"]];
 [self.app.sheets.firstMatch.buttons[@"brewfile.review.install"] click];
 XCUIElement *action = self.app.sheets.firstMatch.buttons[@"brewfile.import.action"];
 XCTAssertTrue([action waitForExistenceWithTimeout:5]);
 XCTAssertEqualObjects(action.title, @"Cancel");
 [action click];
 XCUIElement *status = self.app.staticTexts[@"brewfile.import.status"];
 [self expectationForPredicate:[NSPredicate predicateWithFormat:@"value == %@", @"Import cancelled. Some changes may already have been made."] evaluatedWithObject:status handler:nil];
 [self waitForExpectationsWithTimeout:10 handler:nil];
 XCTAssertEqualObjects(action.title, @"Close");
 NSString *output = self.app.textViews[@"brewfile.import.output"].value;
 XCTAssertTrue([output containsString:@"MOCK_IMPORT_STARTED"]);
 XCTAssertTrue([output containsString:@"MOCK_IMPORT_CANCELLED"]);
 XCTAssertFalse([output containsString:@"MOCK_IMPORT_OK"]);
 [action click];
 XCTAssertFalse(self.app.sheets.firstMatch.exists);
}

- (void)testBrewfileImportFailureRemainsVisible
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'" extraArguments:@[@"-BPMockBrewfileImportFails"]];
 [self.app.sheets.firstMatch.buttons[@"brewfile.review.install"] click];
 XCUIElement *status = self.app.staticTexts[@"brewfile.import.status"];
 XCTAssertTrue([status waitForExistenceWithTimeout:5]);
 [self expectationForPredicate:[NSPredicate predicateWithFormat:@"value BEGINSWITH %@", @"Import failed."] evaluatedWithObject:status handler:nil];
 [self waitForExpectationsWithTimeout:10 handler:nil];
 XCTAssertTrue([self.app.textViews[@"brewfile.import.output"].value containsString:@"MOCK_IMPORT_FAILED"]);
 [self.app.sheets.firstMatch.buttons[@"brewfile.import.action"] click];
}

- (NSArray *)germanBrewfileArguments
{
 return @[@"-AppleLanguages", @"(de)", @"-AppleLocale", @"de_DE"];
}

- (void)testGermanBrewfileReviewAndCancel
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'\ncask 'missingapp'\ntap 'owner/tap'\nmas 'App', id: 123\nvscode 'pub.ext'" extraArguments:[self germanBrewfileArguments]];
 XCUIElement *sheet = self.app.sheets.firstMatch;
 NSString *review = sheet.textViews[@"brewfile.review.entries"].value;
 XCTAssertTrue([review containsString:@"mockwget — Installiert"]);
 XCTAssertTrue([review containsString:@"missingapp — Fehlt"]);
 XCTAssertTrue([review containsString:@"Nicht geprüft"]);
 XCTAssertTrue([review containsString:@"Mac App Store"]);
 XCTAssertTrue(sheet.staticTexts[@"Brewfile prüfen"].exists);
 NSPredicate *warning = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"Installationsskripte ausführen"];
 XCTAssertTrue([sheet.staticTexts matchingPredicate:warning].firstMatch.exists);
 XCTAssertEqualObjects(sheet.buttons[@"brewfile.review.install"].title, @"Geprüfte Einträge installieren");
 XCTAssertEqualObjects(sheet.buttons[@"brewfile.review.cancel"].title, @"Abbrechen");
 [sheet.buttons[@"brewfile.review.cancel"] click];
 XCTAssertFalse(self.app.sheets.firstMatch.exists);
 XCTAssertFalse(self.app.textViews[@"brewfile.import.output"].exists);
}

- (void)testGermanBrewfileReviewEscapeRunsNothing
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'" extraArguments:[self germanBrewfileArguments]];
 XCUIElement *sheet = self.app.sheets.firstMatch;
 XCUIElement *cancel = sheet.buttons[@"brewfile.review.cancel"];
 BOOL localizedReview = sheet.staticTexts[@"Brewfile prüfen"].exists &&
  [sheet.textViews[@"brewfile.review.entries"].value containsString:@"mockwget — Installiert"] &&
  [cancel.title isEqualToString:@"Abbrechen"];
 XCUIApplicationState applicationState = self.app.state;
 XCTAssertTrue(localizedReview);
 XCTAssertEqual(applicationState, XCUIApplicationStateRunningForeground);
 if (!localizedReview || applicationState != XCUIApplicationStateRunningForeground) return;

 [self.app typeKey:XCUIKeyboardKeyEscape modifierFlags:XCUIKeyModifierNone];
 [self expectationForPredicate:[NSPredicate predicateWithFormat:@"exists == NO"]
  evaluatedWithObject:self.app.sheets.firstMatch handler:nil];
 [self waitForExpectationsWithTimeout:5 handler:nil];
 XCTAssertFalse(self.app.sheets.firstMatch.exists);
 XCTAssertFalse(self.app.textViews[@"brewfile.import.output"].exists);
 XCTAssertFalse(self.app.staticTexts[@"brewfile.import.status"].exists);
}

- (void)testGermanBrewfileUnsupportedWarning
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'\nsystem('unsafe')" extraArguments:[self germanBrewfileArguments]];
 XCUIElement *sheet = self.app.sheets.firstMatch;
 XCTAssertFalse(sheet.buttons[@"brewfile.review.install"].enabled);
 NSString *review = sheet.textViews[@"brewfile.review.entries"].value;
 XCTAssertTrue([review containsString:@"Zeile 2:"]);
 XCTAssertTrue([review containsString:@"Es wird nichts installiert."]);
 [sheet.buttons[@"brewfile.review.cancel"] click];
}

- (void)assertGermanImportWithArguments:(NSArray *)arguments expectedStatus:(NSString *)expected outputMarker:(NSString *)marker cancel:(BOOL)cancel
{
 [self openBrewfileReviewWithContents:@"brew 'mockwget'" extraArguments:[[self germanBrewfileArguments] arrayByAddingObjectsFromArray:arguments]];
 [self.app.sheets.firstMatch.buttons[@"brewfile.review.install"] click];
 XCUIElement *action = self.app.sheets.firstMatch.buttons[@"brewfile.import.action"];
 XCTAssertTrue([action waitForExistenceWithTimeout:5]);
 if (cancel) {
  XCTAssertEqualObjects(action.title, @"Abbrechen");
  [action click];
 }
 XCUIElement *status = self.app.staticTexts[@"brewfile.import.status"];
 [self expectationForPredicate:[NSPredicate predicateWithFormat:@"value == %@", expected] evaluatedWithObject:status handler:nil];
 [self waitForExpectationsWithTimeout:10 handler:nil];
 XCTAssertEqualObjects(action.title, @"Schließen");
 NSString *output = self.app.textViews[@"brewfile.import.output"].value;
 if (cancel) {
  XCTAssertTrue([output containsString:@"MOCK_IMPORT_STARTED"]);
  XCTAssertTrue([output containsString:@"MOCK_IMPORT_CANCELLED"]);
  XCTAssertFalse([output containsString:@"MOCK_IMPORT_OK"]);
 }
 else XCTAssertTrue([output containsString:marker]);
 [action click];
 XCTAssertFalse(self.app.sheets.firstMatch.exists);
}

- (void)testGermanBrewfileConfirmedImport
{
 [self assertGermanImportWithArguments:@[] expectedStatus:@"Import abgeschlossen." outputMarker:@"MOCK_IMPORT_OK" cancel:NO];
}

- (void)testGermanBrewfileFailedImport
{
 [self assertGermanImportWithArguments:@[@"-BPMockBrewfileImportFails"] expectedStatus:@"Import fehlgeschlagen. Weitere Informationen finden Sie in der Ausgabe." outputMarker:@"MOCK_IMPORT_FAILED" cancel:NO];
}

- (void)testGermanBrewfileCancelledImport
{
 [self assertGermanImportWithArguments:@[@"-BPMockHoldBrewfileImportUntilCancelled"] expectedStatus:@"Import abgebrochen. Es können bereits Änderungen vorgenommen worden sein." outputMarker:nil cancel:YES];
}

- (void)openGermanMockExportWithArguments:(NSArray *)arguments
{
 [self launchWithArguments:[[@[@"-BPMockBrew", @"-BPMockExportURL", @"/fixture/Brewfile"] arrayByAddingObjectsFromArray:[self germanBrewfileArguments]] arrayByAddingObjectsFromArray:arguments]];
 // AppKit exposes the existing German submenu title (Tools) in the menu bar.
 [self.app.menuBars.menuBarItems[@"Tools"] click];
 [self.app.menuItems[@"Exportiere Brew Installation..."] click];
}

- (void)testGermanBrewfileSlowAndSuccessfulExport
{
 [self openGermanMockExportWithArguments:@[@"-BPMockSlowExport"]];
 XCUIElement *close = self.app.sheets.firstMatch.buttons[@"brewfile.export.close"];
 XCTAssertTrue([close waitForExistenceWithTimeout:10]);
 XCTAssertEqualObjects(close.title, @"Schließen");
 XCTAssertFalse(close.enabled);
 XCTAssertTrue([self.app descendantsMatchingType:XCUIElementTypeAny][@"brewfile.export.progress"].exists);
 XCTAssertTrue(self.app.sheets.firstMatch.staticTexts[@"Bitte warten, während die Datei generiert wird."].exists);
 [self expectationForPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] evaluatedWithObject:close handler:nil];
 [self waitForExpectationsWithTimeout:15 handler:nil];
 XCTAssertEqualObjects(self.app.staticTexts[@"brewfile.export.status"].value, @"Export erfolgreich");
 [close click];
 XCTAssertFalse(self.app.sheets.firstMatch.exists);
}

- (void)testGermanBrewfileFailedExport
{
 [self openGermanMockExportWithArguments:@[@"-BPMockExportFails"]];
 XCUIElement *status = self.app.staticTexts[@"brewfile.export.status"];
 XCTAssertTrue([status waitForExistenceWithTimeout:10]);
 XCTAssertEqualObjects(status.value, @"Export fehlgeschlagen");
 XCTAssertTrue([self.app.staticTexts[@"brewfile.export.detail"].value containsString:@"MOCK_EXPORT_FAILED"]);
 XCUIElement *close = self.app.sheets.firstMatch.buttons[@"brewfile.export.close"];
 XCTAssertEqualObjects(close.title, @"Schließen");
 XCTAssertTrue(close.enabled);
 [close click];
 XCTAssertFalse(self.app.sheets.firstMatch.exists);
}

// Smoke test: the app launches and presents its main window.
- (void)testAppLaunchesAndShowsMainWindow
{
	[self launchWithArguments:@[]];
}

// Unavailable Homebrew cannot satisfy the normal helper's mockwget settle
// wait. Only these recovery journeys use this distinct launch path.
- (void)launchRecoveryWithArguments:(NSArray<NSString *> *)arguments
{
	self.app.launchArguments = [@[@"-BPMockBrew", @"-BPLastSelectedSidebarRow", @"1",
		@"-BPSortColumnIdentifier", @""] arrayByAddingObjectsFromArray:arguments];
	[self.app launch];
	XCTAssertTrue([self.app.windows.firstMatch waitForExistenceWithTimeout:30]);
	XCTAssertTrue([self.app.buttons[@"homebrew.retry"] waitForExistenceWithTimeout:30]);
}

- (void)testMissingHomebrewShowsActionableNonmodalRecovery
{
	[self launchRecoveryWithArguments:@[@"-BPMockHomebrewMissing"]];
	XCTAssertTrue(self.app.buttons[@"homebrew.install"].exists);
	XCTAssertTrue(self.app.buttons[@"homebrew.retry"].enabled);
	XCTAssertTrue(self.app.staticTexts[@"homebrew.recovery.message"].exists);
	XCTAssertGreaterThan(self.app.staticTexts[@"homebrew.recovery.message"].frame.size.height, 30.0);
	XCTAssertEqual(self.app.sheets.count, 0u);
	XCTAssertEqual(self.app.dialogs.count, 0u);
	XCTAssertFalse([self formulaCellWithName:@"mockwget"].exists);
}

- (void)testPersistentHomebrewFailureRemainsRetryableWithoutDuplicateRecovery
{
	[self launchRecoveryWithArguments:@[@"-BPMockHomebrewMissing", @"-BPMockSlowHomebrewRetry"]];
	XCUIElement *retry = self.app.buttons[@"homebrew.retry"];
	[retry click];
	XCTAssertFalse(retry.enabled);
	NSPredicate *enabled = [NSPredicate predicateWithFormat:@"enabled == YES"];
	XCTAssertEqual([XCTWaiter waitForExpectations:@[[[XCTNSPredicateExpectation alloc] initWithPredicate:enabled object:retry]] timeout:10], XCTWaiterResultCompleted);
	XCTAssertEqual([self.app.buttons matchingIdentifier:@"homebrew.retry"].count, 1u);
	XCTAssertEqual(self.app.sheets.count, 0u);
	XCTAssertFalse([self formulaCellWithName:@"mockwget"].exists);
}

- (void)testHomebrewRetryRecoversInstalledPackagesWithoutRelaunching
{
	[self launchRecoveryWithArguments:@[@"-BPMockHomebrewRecovers", @"-BPMockSlowHomebrewRetry"]];
	XCUIElement *retry = self.app.buttons[@"homebrew.retry"];
	[retry click];
	XCTAssertFalse(retry.enabled);
	XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:30]);
	XCTAssertFalse(self.app.buttons[@"homebrew.retry"].exists);
	[self assertSelectedSidebarIdentifier:@"sidebar.formulae.installed"];
	XCTAssertEqual(self.app.sheets.count, 0u);
}

#pragma mark - Sidebar navigation journeys

// Notification launch journeys start somewhere other than Installed, so they
// cannot use the shared helper's Installed-list settle wait.
- (void)launchWithPendingNotificationTarget:(NSString *)target
{
	self.app.launchArguments = @[ @"-BPMockBrew", @"-BPMockHoldCatalogUntilReleased",
		@"-BPMockNotificationTarget", target, @"-BPLastSelectedSidebarRow", @"1",
		@"-BPSortColumnIdentifier", @"" ];
	[self.app launch];
	XCTAssertTrue([self.app.windows.firstMatch waitForExistenceWithTimeout:30.0]);
	XCTAssertTrue([self.app.buttons[@"Stop Reloading"] waitForExistenceWithTimeout:30.0],
		@"the journey must observe the initial reload before its completion");
}

- (void)assertSelectedSidebarIdentifier:(NSString *)identifier
{
	XCUIElement *row = [self.app.outlines.firstMatch.outlineRows containingType:XCUIElementTypeStaticText
		identifier:identifier].firstMatch;
	XCTNSPredicateExpectation *selected = [[XCTNSPredicateExpectation alloc]
		initWithPredicate:[NSPredicate predicateWithFormat:@"exists == YES AND selected == YES"] object:row];
	XCTWaiterResult result = [XCTWaiter waitForExpectations:@[selected] timeout:30.0];
	if (result != XCTWaiterResultCompleted) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertEqual(result, XCTWaiterResultCompleted, @"%@ should be the selected sidebar destination", identifier);
}

- (void)waitForNotificationLaunchReloadToFinish
{
	NSPredicate *finished = [NSPredicate predicateWithFormat:@"exists == NO"];
	[self expectationForPredicate:finished evaluatedWithObject:self.app.buttons[@"Stop Reloading"] handler:nil];
	[self waitForExpectationsWithTimeout:30.0 handler:nil];
}

- (void)assertPendingNotificationTarget:(NSString *)target
					selectsSidebar:(NSString *)identifier
					   fixtureName:(NSString *)fixtureName
{
	[self launchWithPendingNotificationTarget:target];
	[self assertSelectedSidebarIdentifier:identifier];
	XCTAssertTrue(self.app.buttons[@"Stop Reloading"].exists, @"selection must be observed before normal completion");
	[self clickNotificationTestMenuItem:@"mock.catalog.complete"];
	[self waitForNotificationLaunchReloadToFinish];
	[self assertSelectedSidebarIdentifier:identifier];
	XCTAssertTrue([[self formulaCellWithName:fixtureName] waitForExistenceWithTimeout:15.0],
		@"the notification destination should display its outdated package");
	XCTAssertFalse([self formulaCellWithName:@"mockwget"].exists,
		@"an outdated notification must not leave the Installed formulae list selected");
	XCTAssertFalse([self formulaCellWithName:@"mockvscode"].exists,
		@"cask notifications must select Outdated, not Installed Casks");
}

- (void)testPendingFormulaeNotificationSurvivesInitialReload
{
	[self assertPendingNotificationTarget:@"formulae" selectsSidebar:@"sidebar.formulae.outdated"
		fixtureName:@"mockgit"];
}

- (void)testPendingCaskNotificationSurvivesInitialReload
{
	[self assertPendingNotificationTarget:@"casks" selectsSidebar:@"sidebar.casks.outdated"
		fixtureName:@"mockchrome"];
}

- (void)testPendingMixedNotificationOpensFormulaeAndSurvivesInitialReload
{
	[self assertPendingNotificationTarget:@"mixed" selectsSidebar:@"sidebar.formulae.outdated"
		fixtureName:@"mockgit"];
}

- (void)testPendingNotificationDoesNotReplayAfterUserNavigatesDuringReload
{
	[self launchWithPendingNotificationTarget:@"casks"];
	[self assertSelectedSidebarIdentifier:@"sidebar.casks.outdated"];
	XCTAssertTrue(self.app.buttons[@"Stop Reloading"].exists, @"navigation must start while the reload is held");
	[[self sidebarRow:@"sidebar.formulae.installed"] click];
	[self assertSelectedSidebarIdentifier:@"sidebar.formulae.installed"];
	XCTAssertTrue(self.app.buttons[@"Stop Reloading"].exists, @"user navigation must precede normal completion");
	[self clickNotificationTestMenuItem:@"mock.catalog.complete"];
	[self waitForNotificationLaunchReloadToFinish];
	[self assertSelectedSidebarIdentifier:@"sidebar.formulae.installed"];
	XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:15.0],
		@"finishing the reload must keep the user's later navigation");
	XCTAssertFalse([self formulaCellWithName:@"mockchrome"].exists);
}

// The mock-only menu drives real controller actions without typing into a
// non-key window on CI. It carries semantic payloads, never sidebar row logic.
- (void)clickNotificationTestMenuItem:(NSString *)title
{
	[self.app.menuBars.menuBarItems[@"Notification Test"] click];
	[self.app.menuItems[title] click];
}

- (void)assertWarmNotificationTarget:(NSString *)target
					 selectsSidebar:(NSString *)identifier
						fixtureName:(NSString *)fixtureName
					alreadySelected:(BOOL)alreadySelected
					  pendingSearch:(BOOL)pendingSearch
{
	[self launchWithArguments:@[@"-BPMockBrew", @"-BPMockWarmNotificationTarget", target]];
	[self waitForNotificationLaunchReloadToFinish];
	if (alreadySelected)
	{
		[[self sidebarRow:identifier] click];
		[self assertSelectedSidebarIdentifier:identifier];
		XCTAssertTrue([[self formulaCellWithName:fixtureName] waitForExistenceWithTimeout:15.0]);
	}

	if (pendingSearch)
	{
		// Queue the 150 ms debounce and route the notification in the same event.
		[self clickNotificationTestMenuItem:@"Search Then Open Mock Notification"];
		XCTNSPredicateExpectation *noLateSearch = [[XCTNSPredicateExpectation alloc]
			initWithPredicate:[NSPredicate predicateWithFormat:@"exists == YES"]
			object:[self formulaCellWithName:@"mockvscode"]];
		noLateSearch.inverted = YES;
		XCTAssertEqual([XCTWaiter waitForExpectations:@[noLateSearch] timeout:1.0], XCTWaiterResultCompleted,
			@"a pending debounce must not restart search after notification navigation");
	}
	else
	{
		[self clickNotificationTestMenuItem:@"Search Mock Packages"];
		XCTAssertTrue([[self formulaCellWithName:@"mockvscode"] waitForExistenceWithTimeout:15.0],
			@"the journey must observe real search results before routing the notification");
		XCTAssertEqualObjects(self.app.searchFields.firstMatch.value, @"mockvscode");
		[self clickNotificationTestMenuItem:@"Open Mock Notification"];
	}

	[self assertSelectedSidebarIdentifier:identifier];
	XCTAssertEqualObjects(self.app.searchFields.firstMatch.value, @"",
		@"notification navigation should clear the search field");
	BOOL appeared = [[self formulaCellWithName:fixtureName] waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the outdated destination must remain visible after leaving search");
	XCTAssertFalse([self formulaCellWithName:@"mockvscode"].exists,
		@"the table should show the outdated destination, not stale search results");
	XCTAssertFalse([self formulaCellWithName:@"mockwget"].exists);
}

- (void)testFormulaeNotificationLeavesSearchForOutdatedDestination
{
	[self assertWarmNotificationTarget:@"formulae" selectsSidebar:@"sidebar.formulae.outdated"
		fixtureName:@"mockgit" alreadySelected:NO pendingSearch:NO];
}

- (void)testCaskNotificationLeavesSearchForOutdatedDestination
{
	[self assertWarmNotificationTarget:@"casks" selectsSidebar:@"sidebar.casks.outdated"
		fixtureName:@"mockchrome" alreadySelected:NO pendingSearch:NO];
}

- (void)testFormulaeNotificationLeavesSearchOnAlreadySelectedDestination
{
	[self assertWarmNotificationTarget:@"formulae" selectsSidebar:@"sidebar.formulae.outdated"
		fixtureName:@"mockgit" alreadySelected:YES pendingSearch:NO];
}

- (void)testCaskNotificationLeavesSearchOnAlreadySelectedDestination
{
	[self assertWarmNotificationTarget:@"casks" selectsSidebar:@"sidebar.casks.outdated"
		fixtureName:@"mockchrome" alreadySelected:YES pendingSearch:NO];
}

- (void)testFormulaeNotificationCancelsPendingSearch
{
	[self assertWarmNotificationTarget:@"formulae" selectsSidebar:@"sidebar.formulae.outdated"
		fixtureName:@"mockgit" alreadySelected:NO pendingSearch:YES];
}

- (void)testCaskNotificationCancelsPendingSearch
{
	[self assertWarmNotificationTarget:@"casks" selectsSidebar:@"sidebar.casks.outdated"
		fixtureName:@"mockchrome" alreadySelected:NO pendingSearch:YES];
}

// Journey: the sidebar presents every navigation destination.
// Runs with the mock: a real-brew launch spawns a full `brew` reload whose
// subprocesses outlive the test when the app is terminated, and the orphaned
// work has caused timeouts in whichever mock test runs next on CI.
- (void)testSidebarShowsAllNavigationItems
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];
	XCUIElement *sidebar = [self sidebar];
	// By identifier, so both "Installed" rows and both "Outdated" rows are
	// asserted rather than one standing in for the other.
	NSArray<NSString *> *items = @[ @"sidebar.formulae.installed", @"sidebar.formulae.outdated",
									@"sidebar.formulae.all", @"sidebar.formulae.leaves",
									@"sidebar.formulae.pinned", @"sidebar.formulae.repositories",
									@"sidebar.casks.installed", @"sidebar.casks.outdated",
									@"sidebar.casks.all",
									@"sidebar.tools.doctor", @"sidebar.tools.update",
									@"sidebar.tools.services" ];
	for (NSString *item in items) {
		XCTAssertTrue([sidebar.staticTexts[item] waitForExistenceWithTimeout:15.0],
					  @"the sidebar should show the %@ row", item);
	}
}

// Journey: selecting a Tools item switches the content to that tool's view.
// Mock-launched for the same reason as testSidebarShowsAllNavigationItems.
- (void)testNavigatingToToolViewsFromSidebar
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *doctorItem = [self sidebarRow:@"sidebar.tools.doctor"];
	XCTAssertTrue([doctorItem waitForExistenceWithTimeout:15.0], @"Doctor item should exist");
	[doctorItem click];
	XCTAssertTrue([self.app.staticTexts[@"Homebrew Doctor"] waitForExistenceWithTimeout:15.0],
				  @"selecting Doctor should show the Homebrew Doctor view");

	XCUIElement *updateItem = [self sidebarRow:@"sidebar.tools.update"];
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

	[[self sidebarRow:@"sidebar.formulae.all"] click];
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

	[[self sidebarRow:@"sidebar.formulae.all"] click];
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
	[[self sidebarRow:@"sidebar.formulae.pinned"] click];

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

	XCUIElement *installedCasks = [self sidebarRow:@"sidebar.casks.installed"];
	XCTAssertTrue([installedCasks waitForExistenceWithTimeout:30.0], @"sidebar should load");
	[installedCasks click];

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

	XCUIElement *outdatedCasks = [self sidebarRow:@"sidebar.casks.outdated"];
	XCTAssertTrue([outdatedCasks waitForExistenceWithTimeout:30.0], @"sidebar should load");
	[outdatedCasks click];

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

	// A cask: the box should be offered.
	[[self sidebarRow:@"sidebar.casks.installed"] click];
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
	[[self sidebarRow:@"sidebar.formulae.installed"] click];
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

// Journey: confirming an install actually runs it against the mock.
//
// Every other mutating journey stops at Cancel, which is why the missing mock
// overrides went unnoticed — the operations they guarded were never reached.
// This one goes through, so it fails if the mock ever stops covering install.
- (void)testConfirmingAnInstallRunsAgainstTheMock
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	[[self sidebarRow:@"sidebar.formulae.all"] click];
	XCUIElement *htop = [self formulaCellWithName:@"mockhtop"];
	XCTAssertTrue([htop waitForExistenceWithTimeout:30.0], @"mockhtop should be listed under All Formulae");
	[htop click];

	XCUIElement *installButton = self.app.buttons[@"Install Formula"];
	XCTAssertTrue([installButton waitForExistenceWithTimeout:15.0]);
	[installButton click];

	// Scoped to the sheet, not the app. An alert's buttons are mirrored to the
	// Touch Bar, so an app-wide query matches twice — and firstMatch can pick
	// the Touch Bar element, which is not clickable.
	XCUIElement *sheet = self.app.sheets.firstMatch;
	XCTAssertTrue([sheet waitForExistenceWithTimeout:15.0], @"the confirmation should appear");
	[sheet.buttons[@"Yes"] click];

	// The marker proves the mock served this, not real brew.
	NSPredicate *streamed = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"MOCK_INSTALL_OK"];
	XCUIElement *output = [[self.app.textViews matchingPredicate:streamed] firstMatch];
	BOOL appeared = [output waitForExistenceWithTimeout:20.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the operation window should stream the mock's install output");
}

- (void)testClearingQueuedSearchKeepsInstalledFormulaeVisible
{
	[self launchWithArguments:@[@"-BPMockBrew", @"-BPMockWarmNotificationTarget", @"casks"]];
	[self waitForNotificationLaunchReloadToFinish];
	[self assertSelectedSidebarIdentifier:@"sidebar.formulae.installed"];
	XCTAssertTrue([self formulaCellWithName:@"mockwget"].exists);
	XCTAssertTrue([self formulaCellWithName:@"mockgit"].exists);
	XCTAssertFalse([self formulaCellWithName:@"mockvscode"].exists);

	// Queue and clear within one main event, before the 150 ms debounce fires.
	// The mock menu drives the toolbar text-change path without keyboard focus.
	[self clickNotificationTestMenuItem:@"Search Then Clear Mock Search"];
	XCTAssertEqualObjects(self.app.searchFields.firstMatch.value, @"");
	XCTNSPredicateExpectation *noLateSearch = [[XCTNSPredicateExpectation alloc]
		initWithPredicate:[NSPredicate predicateWithFormat:@"exists == YES"]
		object:[self formulaCellWithName:@"mockvscode"]];
	noLateSearch.inverted = YES;
	XCTWaiterResult result = [XCTWaiter waitForExpectations:@[noLateSearch] timeout:1.0];
	if (result != XCTWaiterResultCompleted) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertEqual(result, XCTWaiterResultCompleted,
		@"clearing before debounce must not display late search results");
	[self assertSelectedSidebarIdentifier:@"sidebar.formulae.installed"];
	XCTAssertEqualObjects(self.app.searchFields.firstMatch.value, @"");
	XCTAssertTrue([self formulaCellWithName:@"mockwget"].exists);
	XCTAssertTrue([self formulaCellWithName:@"mockgit"].exists);
	XCTAssertFalse([self formulaCellWithName:@"mockvscode"].exists);
}

// Journey: searching finds casks, and does not move the user out of the list
// they were browsing.
//
// Search used to walk only allFormulae, so a cask token returned nothing, and
// it force-selected Formulae ▸ All — so someone browsing All Casks who typed
// three characters landed in the formula namespace looking at an empty table.
- (void)testSearchingFindsCasksAndKeepsTheSidebarSelection
{
	[self launchWithArguments:@[@"-BPMockBrew", @"-BPMockWarmNotificationTarget", @"casks"]];
	[self waitForNotificationLaunchReloadToFinish];
	XCUIElement *sidebar = [self sidebar];

	[[self sidebarRow:@"sidebar.casks.all"] click];
	XCTAssertTrue([[self formulaCellWithName:@"mockchrome"] waitForExistenceWithTimeout:30.0],
				  @"All Casks should list the mock casks");
	NSInteger rowBefore = [self selectedSidebarRow:sidebar];

	// The existing mock menu drives the same search entry point without typing,
	// which needs a key window unavailable on CI.
	XCUIElement *searchField = self.app.searchFields.firstMatch;
	XCTAssertTrue([searchField waitForExistenceWithTimeout:15.0], @"the toolbar should offer a search field");
	[self clickNotificationTestMenuItem:@"Search Mock Packages"];
	// mockvscode was already in All Casks. Wait for a nonmatching cask to
	// disappear so that observing it now proves the debounced search finished.
	XCTAssertTrue([[self formulaCellWithName:@"mockchrome"] waitForNonExistenceWithTimeout:15.0]);
	XCTAssertTrue([[self formulaCellWithName:@"mockvscode"] waitForExistenceWithTimeout:15.0],
		@"the search must return the matching cask");
	XCTAssertEqualObjects(searchField.value, @"mockvscode");
	XCTAssertFalse([self formulaCellWithName:@"mockchrome"].exists);
	XCTAssertFalse([self formulaCellWithName:@"mockwget"].exists);
	[self assertSelectedSidebarIdentifier:@"sidebar.casks.all"];

	XCTAssertEqual([self selectedSidebarRow:sidebar], rowBefore,
				   @"searching casks should preserve the sidebar selection");
}

/// Index of the selected sidebar row, or -1.
- (NSInteger)selectedSidebarRow:(XCUIElement *)sidebar
{
	NSArray<XCUIElement *> *rows = sidebar.outlineRows.allElementsBoundByIndex;
	for (NSUInteger i = 0; i < rows.count; i++)
	{
		if (rows[i].isSelected) { return (NSInteger)i; }
	}
	return -1;
}

// Journey: an empty list explains itself rather than showing column headers
// over blank space.
//
// Outdated being empty is the happy path, and it used to look identical to a
// list that had failed to load.
- (void)testAnEmptyListShowsAnExplanation
{
	[self launchWithArguments:@[ @"-BPMockBrew", @"-BPMockEmptyOutdated" ]];

	[[self sidebarRow:@"sidebar.formulae.outdated"] click];

	XCUIElement *explanation = self.app.staticTexts[@"Everything Is Up to Date"];
	BOOL appeared = [explanation waitForExistenceWithTimeout:20.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"an empty Outdated list should say so");
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

	[[self sidebarRow:@"sidebar.tools.services"] click];

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

- (void)waitForServiceDetailsContaining:(NSString *)text
{
	XCUIElement *details = self.app.textViews[@"services.details"];
	XCTAssertTrue([details waitForExistenceWithTimeout:10]);
	NSPredicate *contains = [NSPredicate predicateWithFormat:@"value CONTAINS %@", text];
	XCTNSPredicateExpectation *expectation = [[XCTNSPredicateExpectation alloc] initWithPredicate:contains object:details];
	XCTAssertEqual([XCTWaiter waitForExpectations:@[expectation] timeout:10], XCTWaiterResultCompleted,
		@"CAKEBREW_UI_TREE_SERVICE_DETAILS\n%@", self.app.debugDescription);
}

- (void)testServiceDetailsFollowRunningAndStoppedSelection
{
	[self launchWithArguments:@[@"-BPMockBrew"]];
	[[self sidebarRow:@"sidebar.tools.services"] click];
	XCUIElement *postgres = [self formulaCellWithName:@"mockpostgres"];
	XCTAssertTrue([postgres waitForExistenceWithTimeout:15]);
	[postgres click];
	[self waitForServiceDetailsContaining:@"PID: 123    User: mockuser"];
	XCTAssertTrue(self.app.buttons[@"services.copyOutput"].enabled);
	XCTAssertFalse(self.app.buttons[@"services.openLogs"].enabled);
	XCTAssertFalse(self.app.buttons[@"services.revealFile"].enabled);
	[[self formulaCellWithName:@"mockredis"] click];
	[self waitForServiceDetailsContaining:@"Service: mockredis"];
	[self waitForServiceDetailsContaining:@"PID: Not available"];
	XCTAssertTrue([self formulaCellWithName:@"mockpostgres"].exists);
}

- (void)testServiceDetailFailureKeepsListAndRawDiagnostic
{
	[self launchWithArguments:@[@"-BPMockBrew", @"-BPMockServiceDetailsFailure"]];
	[[self sidebarRow:@"sidebar.tools.services"] click];
	XCUIElement *postgres = [self formulaCellWithName:@"mockpostgres"];
	XCTAssertTrue([postgres waitForExistenceWithTimeout:15]);
	[postgres click];
	[self waitForServiceDetailsContaining:@"Error: mock service details unavailable"];
	[self waitForServiceDetailsContaining:@"The mock service list is still available."];
	NSString *details = self.app.textViews[@"services.details"].value;
	XCTAssertTrue([details hasPrefix:@"Could not load service details. Homebrew reported:\nError: mock service details unavailable"],
		@"Failure and diagnostic must appear first without scrolling past metadata placeholders.");
	XCTAssertTrue([self formulaCellWithName:@"mockpostgres"].exists);
	XCTAssertTrue([self formulaCellWithName:@"mockredis"].exists);
	XCTAssertTrue(self.app.buttons[@"services.copyOutput"].enabled);
	XCTAssertFalse(self.app.buttons[@"services.openLogs"].enabled);
	XCTAssertTrue(self.app.buttons[@"Stop"].enabled);
}

// Journey: selecting a cask shows the detail pane populated from
// `brew info --cask` (description parsed from the cask output shape).
- (void)testSelectingCaskShowsCaskInfoInDetailPane
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *installedCasks = [self sidebarRow:@"sidebar.casks.installed"];
	XCTAssertTrue([installedCasks waitForExistenceWithTimeout:30.0], @"sidebar should load");
	[installedCasks click];

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

	[[self sidebarRow:@"sidebar.casks.all"] click];

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

	XCUIElement *installedCasks = [self sidebarRow:@"sidebar.casks.installed"];
	XCTAssertTrue([installedCasks waitForExistenceWithTimeout:30.0], @"sidebar should load");
	[installedCasks click];

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

	// Two "Outdated" rows exist (Formulae + Casks); the formulae one is first.
	[[self sidebarRow:@"sidebar.formulae.outdated"] click];
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

	// Two "Outdated" rows exist (Formulae + Casks); the formulae one is first.
	[[self sidebarRow:@"sidebar.formulae.outdated"] click];
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

	[[self sidebarRow:@"sidebar.tools.doctor"] click];
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

	[[self sidebarRow:@"sidebar.formulae.repositories"] click];

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

	[[self sidebarRow:@"sidebar.formulae.repositories"] click];

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
	XCTAssertTrue(searchField.enabled, @"Search must accept input after the initial load, not just exist");
	XCTAssertGreaterThan(searchField.frame.size.width, 0.0);
	XCTAssertGreaterThan(searchField.frame.size.height, 0.0);
}

#pragma mark - Formula info journey

// A transient successful frame is not enough: the previous close animation can
// still complete after a replacement popover has already rendered its content.
- (void)assertMockInformationSurvivesPopoverAnimation
{
    XCTestExpectation *settled = [self expectationWithDescription:@"popover close animation completed"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [settled fulfill];
    });
    [self waitForExpectationsWithTimeout:5.0 handler:nil];
    XCUIElement *title = [[self.app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:@"formula.information.title"].firstMatch;
    XCUIElement *information = [[self.app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:@"formula.information.text"].firstMatch;
    XCTAssertTrue(title.exists);
    XCTAssertTrue([title.label containsString:@"mockwget"]);
    NSPredicate *content = [NSPredicate predicateWithFormat:@"label CONTAINS %@ OR value CONTAINS %@",
        @"A mock formula", @"A mock formula"];
    XCTAssertTrue(information.exists);
    XCTAssertTrue([content evaluateWithObject:information]);
}

- (void)testMoreInformationWhileOpenKeepsSelectedPackageContent
{
    [self launchWithArguments:@[@"-BPMockBrew"]];
    [[self formulaCellWithName:@"mockwget"] click];
    XCUIElement *infoButton = self.app.buttons[@"More Information"];
    [infoButton click];
    XCUIElement *information = [[self.app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:@"formula.information.text"].firstMatch;
    XCTAssertTrue([information waitForExistenceWithTimeout:15.0]);
    [infoButton click];
    [self assertMockInformationSurvivesPopoverAnimation];
}

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
	XCUIElement *infoText = [[self.app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:@"formula.information.text"].firstMatch;
	BOOL appeared = [infoText waitForExistenceWithTimeout:15.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"More Information should show the formula info in a popover");
    NSPredicate *content = [NSPredicate predicateWithFormat:@"label CONTAINS %@ OR value CONTAINS %@",
        @"A mock formula", @"A mock formula"];
    [self expectationForPredicate:content evaluatedWithObject:infoText handler:nil];
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
    XCTAssertGreaterThan(infoText.frame.size.width, 100.0);
    XCTAssertGreaterThan(infoText.frame.size.height, 20.0);
    XCUIElement *title = [[self.app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:@"formula.information.title"].firstMatch;
    XCTAssertTrue([title.label containsString:@"mockwget"]);

    // An outside click dismisses the transient popover and keeps the selection.
    [wget click];
    NSPredicate *dismissed = [NSPredicate predicateWithFormat:@"exists == NO"];
    [self expectationForPredicate:dismissed evaluatedWithObject:infoText handler:nil];
    [self waitForExpectationsWithTimeout:10.0 handler:nil];
    [infoButton click];
    XCTAssertTrue([infoText waitForExistenceWithTimeout:10.0], @"the same selection can reopen information");
}

- (void)testMoreInformationEscapeDismissesAndReopensSelectedPackage
{
    [self launchWithArguments:@[@"-BPMockBrew"]];
    [[self formulaCellWithName:@"mockwget"] click];
    XCUIElement *infoButton = self.app.buttons[@"More Information"];
    XCTAssertTrue([infoButton waitForExistenceWithTimeout:15]);
    [infoButton click];

    XCUIElement *popover = self.app.popovers.firstMatch;
    XCTAssertTrue([popover waitForExistenceWithTimeout:15]);
    XCUIElement *title = [[popover descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:@"formula.information.title"].firstMatch;
    XCUIElement *information = [[popover descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:@"formula.information.text"].firstMatch;
    XCTAssertTrue([information waitForExistenceWithTimeout:15]);
    NSPredicate *content = [NSPredicate predicateWithFormat:@"label CONTAINS %@ OR value CONTAINS %@",
        @"A mock formula", @"A mock formula"];
    BOOL loadedPopover = self.app.popovers.count == 1 && title.exists &&
        [title.label containsString:@"mockwget"] && [content evaluateWithObject:information];
    XCUIApplicationState applicationState = self.app.state;
    XCTAssertTrue(loadedPopover);
    XCTAssertEqual(applicationState, XCUIApplicationStateRunningForeground);
    if (!loadedPopover || applicationState != XCUIApplicationStateRunningForeground) return;

    XCTAttachment *beforeEscape = [XCTAttachment attachmentWithString:self.app.debugDescription];
    beforeEscape.name = @"Loaded information before Escape";
    beforeEscape.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:beforeEscape];
    [self.app typeKey:XCUIKeyboardKeyEscape modifierFlags:XCUIKeyModifierNone];
    BOOL dismissed = [popover waitForNonExistenceWithTimeout:10];
    XCTAssertTrue(dismissed, @"Escape must dismiss the actual popover container");
    if (!dismissed) return;
    XCTAssertFalse(title.exists);
    XCTAssertFalse(information.exists);

    [infoButton click];
    XCTAssertTrue([popover waitForExistenceWithTimeout:10]);
    XCTAssertTrue([information waitForExistenceWithTimeout:10], @"Reopening must restore the selected package information");
    [self assertMockInformationSurvivesPopoverAnimation];
    XCTAssertFalse(self.app.sheets.firstMatch.exists);
}

// Moving between hosted information and the existing AppKit dependents view keeps both routes usable.
- (void)testInformationAndInstalledDependentsUseTheirOwnContent
{
    [self launchWithArguments:@[@"-BPMockBrew"]];
    XCUIElement *wget = [self formulaCellWithName:@"mockwget"];
    [wget doubleClick];
    XCUIElement *information = [[self.app descendantsMatchingType:XCUIElementTypeAny]
        matchingIdentifier:@"formula.information.text"].firstMatch;
    XCTAssertTrue([information waitForExistenceWithTimeout:15.0]);
    [wget click];
    [self.app.menuBars.menuBarItems[@"Formula"] click];
    [self.app.menuItems[@"List Installed Dependents"] click];
    XCUIElement *dependentsTitle = self.app.staticTexts[@"Installed Dependents of Formula: mockwget"];
    XCTAssertTrue([dependentsTitle waitForExistenceWithTimeout:15.0]);
    XCTAssertFalse(information.exists);
    XCTAssertTrue(self.app.textViews.firstMatch.exists);
    [wget click];
    [self.app.buttons[@"More Information"] click];
    XCTAssertTrue([information waitForExistenceWithTimeout:15.0]);
    [self assertMockInformationSurvivesPopoverAnimation];
    XCTAssertFalse(dependentsTitle.exists);
}

#pragma mark - Tools journeys

// Opens Tools > Brew Cleanup and returns the confirmation sheet it presents.
- (XCUIElement *)beginCleanupAndWaitForSheet
{
	XCTAssertTrue([[self formulaCellWithName:@"mockwget"] waitForExistenceWithTimeout:30.0],
				  @"the mock data should load");

	[self.app.menuBars.menuBarItems[@"Tools"] click];
	XCUIElement *cleanupItem = self.app.menuItems[@"Brew Cleanup…"];
	XCTAssertTrue([cleanupItem waitForExistenceWithTimeout:10.0], @"Tools > Brew Cleanup should exist");
	[cleanupItem click];

	// Scoped to the sheet, not the app: an alert's buttons are mirrored to the
	// Touch Bar, so an app-wide query matches twice and firstMatch can pick the
	// mirror, which is not clickable.
	XCUIElement *sheet = self.app.sheets.firstMatch;
	BOOL appeared = [sheet waitForExistenceWithTimeout:20.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"Cleanup should preview what it would remove before deleting anything");
	return sheet;
}

// Journey: a reload names the slow step in the footer rather than running silent.
//
// The loading overlay is built once at setup and comes down on the first
// published list, so it cannot report the catalog fetch — which is the step
// that takes 80+ seconds against real brew. -BPMockSlowCatalog holds the mock's
// catalog calls long enough for the message to be observable.
- (void)testTheCatalogFetchSaysWhatItIsDoing
{
	[self launchWithArguments:@[ @"-BPMockBrew", @"-BPMockSlowCatalog" ]];

	NSPredicate *catalog = [NSPredicate predicateWithFormat:@"value CONTAINS %@ OR label CONTAINS %@",
							@"cask catalog", @"cask catalog"];
	XCUIElement *progress = [[self.app.staticTexts matchingPredicate:catalog] firstMatch];

	BOOL appeared = [progress waitForExistenceWithTimeout:30.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"the slow catalog fetch should say so rather than running silent");

	// And it gets out of the way: once the reload finishes the footer goes back
	// to describing the selected row.
	NSPredicate *description = [NSPredicate predicateWithFormat:@"value CONTAINS %@ OR label CONTAINS %@",
								@"already installed", @"already installed"];
	XCUIElement *restored = [[self.app.staticTexts matchingPredicate:description] firstMatch];

	XCTAssertTrue([restored waitForExistenceWithTimeout:30.0],
				  @"the footer should go back to the row description when the reload ends");
}

// Journey: a running reload offers a way to stop it, and takes it away again.
//
// Deliberately not on the loading overlay: that comes down on the first
// published list, about two seconds in, while the catalog fetch worth stopping
// can take much longer. Hold the mock catalogs until cancellation so the
// Stop control cannot disappear while the journey is locating it.
- (void)testAReloadCanBeStopped
{
	[self launchWithArguments:@[ @"-BPMockBrew", @"-BPMockHoldCatalogUntilCancelled" ]];

	XCUIElement *stop = self.app.buttons[@"Stop Reloading"];
	BOOL appeared = [stop waitForExistenceWithTimeout:30.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"a running reload should offer a way to stop it");

	// Geometry rather than isHittable: hit testing needs a key window, which
	// the CI runner never has.
	XCTAssertTrue(stop.frame.size.width > 0 && stop.frame.size.height > 0,
				  @"the Stop control should have been laid out: %@", NSStringFromRect(stop.frame));

	[stop click];

	// And it goes away, rather than sitting in the toolbar with nothing to stop.
	NSPredicate *gone = [NSPredicate predicateWithFormat:@"exists == NO"];
	[self expectationForPredicate:gone evaluatedWithObject:stop handler:nil];
	[self waitForExpectationsWithTimeout:30.0 handler:nil];
}

// Journey: Tools > Brew Cleanup previews what it would remove, and only cleans
// up once that is confirmed.
- (void)testCleanupConfirmsThenStreamsOutput
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *sheet = [self beginCleanupAndWaitForSheet];

	// The preview has to name what will be lost. The mock's dry run reports
	// three items totalling 49.2MB, so the sheet must say so — a confirmation
	// that only says "are you sure" is the thing this replaced.
	NSPredicate *summary = [NSPredicate predicateWithFormat:@"value CONTAINS %@ OR label CONTAINS %@",
							@"3 items", @"3 items"];
	XCTAssertTrue([sheet.staticTexts matchingPredicate:summary].count > 0,
				  @"the sheet should say how much it would remove");

	[sheet.buttons[@"Yes"] click];

	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"MOCK_CLEANUP_OK"];
	XCUIElement *output = [[self.app.textViews matchingPredicate:predicate] firstMatch];
	BOOL appeared = [output waitForExistenceWithTimeout:20.0];
	if (!appeared) {
		NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
	}
	XCTAssertTrue(appeared, @"confirming should run the cleanup and stream its output");
}

// Journey: cancelling the preview deletes nothing.
//
// The point of the sheet is the escape hatch, so this asserts the operation
// window never opens — the mock's cleanup marker must never appear.
- (void)testCancellingCleanupRunsNothing
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCUIElement *sheet = [self beginCleanupAndWaitForSheet];
	[sheet.buttons[@"Cancel"] click];

	NSPredicate *predicate = [NSPredicate predicateWithFormat:@"value CONTAINS %@", @"MOCK_CLEANUP_OK"];
	XCUIElement *output = [[self.app.textViews matchingPredicate:predicate] firstMatch];

	// Nothing to wait *for*, so wait for the window that would have opened and
	// assert it never does.
	XCTAssertFalse([output waitForExistenceWithTimeout:5.0],
				   @"cancelling should not run a cleanup");
}

// Journey: with nothing to remove, Cleanup says so instead of running.
- (void)testCleanupWithNothingToRemoveSaysSo
{
	[self launchWithArguments:@[ @"-BPMockBrew", @"-BPMockEmptyCleanup" ]];

	XCUIElement *sheet = [self beginCleanupAndWaitForSheet];

	XCTAssertTrue(sheet.buttons[@"OK"].exists,
				  @"the nothing-to-do sheet should acknowledge, not confirm a deletion");
	XCTAssertFalse(sheet.buttons[@"Yes"].exists,
				   @"there is nothing to say yes to");

	[sheet.buttons[@"OK"] click];
}

- (void)openMockExportWithArguments:(NSArray *)arguments
{
 [self launchWithArguments:[@[@"-BPMockBrew", @"-BPMockExportURL", @"/fixture/Brewfile"] arrayByAddingObjectsFromArray:arguments]];
 [self.app.menuBars.menuBarItems[@"Tools"] click];
 [self.app.menuItems[@"Export Brew Installation…"] click];
}

- (void)testExportShowsProgressUntilSuccessAndCloses
{
 [self openMockExportWithArguments:@[@"-BPMockSlowExport"]];
 XCUIElement *close = self.app.sheets.firstMatch.buttons[@"brewfile.export.close"];
 XCTAssertTrue([close waitForExistenceWithTimeout:10]);
 XCTAssertFalse(close.enabled);
 // AppKit spinners expose AXBusyIndicator, not the progress-bar AX role.
 XCUIElement *progress = [self.app descendantsMatchingType:XCUIElementTypeAny][@"brewfile.export.progress"];
 if (!progress.exists) NSLog(@"CAKEBREW_UI_TREE_BEGIN\n%@\nCAKEBREW_UI_TREE_END", self.app.debugDescription);
 XCTAssertTrue(progress.exists);
 XCTAssertFalse(self.app.staticTexts[@"brewfile.export.status"].exists);
 [self expectationForPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] evaluatedWithObject:close handler:nil];
 [self waitForExpectationsWithTimeout:15 handler:nil];
 XCTAssertTrue([self.app.staticTexts[@"brewfile.export.status"].value containsString:@"Successful"]);
 [close click];
 [self expectationForPredicate:[NSPredicate predicateWithFormat:@"exists == NO"] evaluatedWithObject:self.app.sheets.firstMatch handler:nil];
 [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testExportFailureRemainsVisibleUntilClosed
{
 [self openMockExportWithArguments:@[@"-BPMockExportFails"]];
 XCUIElement *status = self.app.staticTexts[@"brewfile.export.status"];
 XCTAssertTrue([status waitForExistenceWithTimeout:10]);
 XCTAssertTrue([status.value containsString:@"Failed"]);
 XCTAssertTrue([self.app.staticTexts[@"brewfile.export.detail"].value containsString:@"MOCK_EXPORT_FAILED"]);
 XCUIElement *close = self.app.sheets.firstMatch.buttons[@"brewfile.export.close"];
 XCTAssertTrue(close.enabled);
 [close click];
 [self expectationForPredicate:[NSPredicate predicateWithFormat:@"exists == NO"] evaluatedWithObject:self.app.sheets.firstMatch handler:nil];
 [self waitForExpectationsWithTimeout:5 handler:nil];
}

- (void)testCancelledExportSaveLeavesAppReadyForAnotherOperation
{
 [self openMockExportWithArguments:@[@"-BPMockExportCancel"]];
 XCTAssertFalse(self.app.sheets.firstMatch.exists);
 [self.app.menuBars.menuBarItems[@"Tools"] click];
 [self.app.menuItems[@"Import Brew Installation…"] click];
 XCTAssertTrue([self.app.sheets.firstMatch waitForExistenceWithTimeout:10]);
 XCTAssertFalse(self.app.sheets.firstMatch.buttons[@"brewfile.export.close"].exists);
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

- (XCUIElement *)openUpgradeAllWithArguments:(NSArray *)arguments
{
    [self launchWithArguments:[@[@"-BPMockBrew"] arrayByAddingObjectsFromArray:arguments]];
    [self.app.menuBars.menuBarItems[@"Formula"] click];
    XCUIElement *upgrade = self.app.menuItems[@"Upgrade All Updates…"];
    XCTAssertTrue([upgrade waitForExistenceWithTimeout:15]);
    XCTNSPredicateExpectation *enabled = [[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithFormat:@"enabled == YES"] object:upgrade];
    XCTAssertEqual([XCTWaiter waitForExpectations:@[enabled] timeout:15], XCTWaiterResultCompleted);
    [upgrade click];
    XCUIElement *confirm = self.app.sheets.firstMatch.buttons[@"updates.confirm"];
    XCTAssertTrue([confirm waitForExistenceWithTimeout:15]);
    return confirm;
}
- (void)testUpgradeAllKeyboardShortcutAndEscapeRunsNothing
{
    [self launchWithArguments:@[@"-BPMockBrew", @"-BPMockMixedUpdates"]];
    BOOL ready = self.app.windows.firstMatch.exists && [self formulaCellWithName:@"mockwget"].exists &&
        !self.app.sheets.firstMatch.exists;
    XCUIApplicationState initialState = self.app.state;
    XCTAssertTrue(ready);
    XCTAssertEqual(initialState, XCUIApplicationStateRunningForeground);
    if (!ready || initialState != XCUIApplicationStateRunningForeground) return;

    [self.app typeKey:@"u" modifierFlags:XCUIKeyModifierCommand | XCUIKeyModifierOption];
    XCUIElement *sheet = self.app.sheets.firstMatch;
    XCUIElement *confirm = sheet.buttons[@"updates.confirm"];
    XCTAssertTrue([confirm waitForExistenceWithTimeout:15]);
    XCUIElement *targets = [sheet.textViews matchingPredicate:[NSPredicate predicateWithFormat:
        @"identifier == 'updates.targets' AND value CONTAINS 'Formulae: mockgit' AND value CONTAINS 'Casks: mockchrome'"]].firstMatch;
    BOOL expectedConfirmation = confirm.exists && targets.exists;
    XCUIApplicationState confirmationState = self.app.state;
    XCTAssertTrue(expectedConfirmation);
    XCTAssertEqual(confirmationState, XCUIApplicationStateRunningForeground);
    if (!expectedConfirmation || confirmationState != XCUIApplicationStateRunningForeground) return;

    [self.app typeKey:XCUIKeyboardKeyEscape modifierFlags:XCUIKeyModifierNone];
    XCTAssertTrue([self.app.sheets.firstMatch waitForNonExistenceWithTimeout:10]);
    XCUIElement *output = [self.app.textViews matchingPredicate:[NSPredicate predicateWithFormat:
        @"value CONTAINS 'MOCK_UPGRADE_' OR value CONTAINS 'brew upgrade'"]].firstMatch;
    XCTAssertFalse(output.exists);
}
- (void)testUpgradeAllPinnedExclusionAndCancelRunsNothing
{
    [self openUpgradeAllWithArguments:@[]];
    XCUIElement *sheet = self.app.sheets.firstMatch;
    XCUIElement *summary = [sheet.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"identifier == 'updates.targets' AND value CONTAINS 'Casks: mockchrome' AND value CONTAINS 'Pinned formulae will be skipped: mockgit'"]].firstMatch;
    XCTAssertTrue(summary.exists);
    [sheet.buttons[@"Cancel"] click];
    XCTAssertTrue([sheet waitForNonExistenceWithTimeout:10]);
    XCTAssertFalse([self.app.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'MOCK_UPGRADE_OK'"]].firstMatch.exists);
}
- (void)testUpgradeAllMixedConfirmationRunsExactNamesAndShowsCommandOutcomes
{
    XCUIElement *confirm = [self openUpgradeAllWithArguments:@[@"-BPMockMixedUpdates"]];
    XCUIElement *summary = [self.app.sheets.firstMatch.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"identifier == 'updates.targets' AND value CONTAINS 'Formulae: mockgit' AND value CONTAINS 'Casks: mockchrome'"]].firstMatch;
    XCTAssertTrue(summary.exists);
    [confirm click];
    XCUIElement *output = [self.app.sheets.firstMatch.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'Command succeeded: brew upgrade --formula mockgit' AND value CONTAINS 'Command succeeded: brew upgrade --cask mockchrome'"]].firstMatch;
    XCTAssertTrue([output waitForExistenceWithTimeout:15]);
    [self.app.sheets.firstMatch.buttons[@"OK"] click];
}
- (void)testUpgradeAllLaterFailurePreservesFirstCommandSuccess
{
    XCUIElement *confirm = [self openUpgradeAllWithArguments:@[@"-BPMockMixedUpdates", @"-BPMockFailedCaskUpgrade"]];
    [confirm click];
    XCUIElement *output = [self.app.sheets.firstMatch.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'Command succeeded: brew upgrade --formula mockgit' AND value CONTAINS 'Command failed; some packages may have changed: brew upgrade --cask mockchrome'"]].firstMatch;
    XCTAssertTrue([output waitForExistenceWithTimeout:15]);
    [self.app.sheets.firstMatch.buttons[@"OK"] click];
}
- (void)testUpgradeAllCaskOnlyEnablesWithNoOutdatedFormulae
{
    XCUIElement *confirm = [self openUpgradeAllWithArguments:@[@"-BPMockEmptyOutdated"]];
    [confirm click];
    XCUIElement *output = [self.app.sheets.firstMatch.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'Command succeeded: brew upgrade --cask mockchrome'"]].firstMatch;
    XCTAssertTrue([output waitForExistenceWithTimeout:15]);
    XCTAssertFalse([output.value containsString:@"--formula"]);
    [self.app.sheets.firstMatch.buttons[@"OK"] click];
}
- (void)testUpgradeAllCancellationReportsActiveAndUnattemptedCommands
{
    XCUIElement *confirm = [self openUpgradeAllWithArguments:@[@"-BPMockMixedUpdates", @"-BPMockSlowUpgrade"]];
    [confirm click];
    XCUIElement *started = [self.app.sheets.firstMatch.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'MOCK_UPGRADE_STARTED'"]].firstMatch;
    XCTAssertTrue([started waitForExistenceWithTimeout:15]);
    [self.app.sheets.firstMatch.buttons[@"Cancel"] click];
    XCUIElement *cancelling = [self.app.sheets.firstMatch.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'MOCK_UPGRADE_CANCELLING'"]].firstMatch;
    XCTAssertTrue([cancelling waitForExistenceWithTimeout:10]);
    XCTAssertFalse(self.app.sheets.firstMatch.buttons[@"OK"].enabled);
    XCUIElement *output = [self.app.sheets.firstMatch.textViews matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'Command cancelled; some packages may have changed: brew upgrade --formula mockgit' AND value CONTAINS 'Command not attempted: brew upgrade --cask mockchrome'"]].firstMatch;
    XCTAssertTrue([output waitForExistenceWithTimeout:15]);
    XCTAssertTrue([self.app.sheets.firstMatch.staticTexts matchingPredicate:[NSPredicate predicateWithFormat:@"value CONTAINS 'Homebrew task cancelled'"]].firstMatch.exists);
    [self.app.sheets.firstMatch.buttons[@"OK"] click];
}
@end
