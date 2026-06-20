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

@end
