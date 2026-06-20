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
	[self.app launch];
}

- (void)tearDown
{
	[self.app terminate];
	self.app = nil;
	[super tearDown];
}

// Smoke test: the app launches and presents its main window. This establishes
// the UI-test target end to end before the navigation-journey tests build on it.
- (void)testAppLaunchesAndShowsMainWindow
{
	XCTAssertTrue([self.app.windows.firstMatch waitForExistenceWithTimeout:15.0],
				  @"The main window should appear after launch");
}

#pragma mark - Sidebar navigation journeys

- (XCUIElement *)sidebar
{
	XCUIElement *sidebar = self.app.outlines.firstMatch;
	XCTAssertTrue([sidebar waitForExistenceWithTimeout:30.0], @"the sidebar outline should appear");
	return sidebar;
}

// Journey: the sidebar presents every navigation destination.
- (void)testSidebarShowsAllNavigationItems
{
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

@end
