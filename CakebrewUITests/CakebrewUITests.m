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

// Journey: launched with the mock brew interface, the Installed list populates
// with the fixture formulae instead of whatever is on the host.
- (void)testInstalledListShowsMockFormulae
{
	[self launchWithArguments:@[ @"-BPMockBrew" ]];

	XCTAssertTrue([self.app.staticTexts[@"mockwget"] waitForExistenceWithTimeout:30.0],
				  @"the mock installed list should populate the formula table");
	XCTAssertTrue([self.app.staticTexts[@"mockgit"] waitForExistenceWithTimeout:15.0],
				  @"the mock installed list should include mockgit");
}

@end
