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

@end
