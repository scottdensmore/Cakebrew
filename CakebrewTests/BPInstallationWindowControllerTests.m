#import <XCTest/XCTest.h>
#import "BPInstallationWindowController.h"
#import "BPAppDelegate.h"

@interface BPInstallationWindowController (SheetLifecycleTests)
- (IBAction)okAction:(id)sender;
@end

// These doubles record the actual controller's sheet calls without creating
// windows, loading nibs, running Homebrew, or changing persistent app state.
@interface BPSheetWindowRecorder : NSObject
@property (weak) NSWindow *sheetParent;
@property (strong) NSWindow *presentedSheet;
@property (copy) void (^sheetCompletion)(NSModalResponse);
@property (strong) NSMutableArray<NSString *> *events;
@property NSUInteger beginCount;
@property NSUInteger endCount;
- (void)beginSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse))completion;
- (void)endSheet:(NSWindow *)sheet;
@end

@implementation BPSheetWindowRecorder
- (void)beginSheet:(NSWindow *)sheet completionHandler:(void (^)(NSModalResponse))completion
{
	self.beginCount++;
	self.presentedSheet = sheet;
	[(BPSheetWindowRecorder *)sheet setSheetParent:(NSWindow *)self];
	self.sheetCompletion = completion;
	[self.events addObject:@"begin"];
}
- (void)endSheet:(NSWindow *)sheet
{
	self.endCount++;
	if (sheet.sheetParent != (NSWindow *)self) return;
	[(BPSheetWindowRecorder *)sheet setSheetParent:nil];
	void (^completion)(NSModalResponse) = self.sheetCompletion;
	self.sheetCompletion = nil;
	self.presentedSheet = nil;
	if (completion) completion(NSModalResponseOK);
}
@end

@interface BPSheetDelegateRecorder : NSObject
@property (strong) NSWindow *window;
@property (nonatomic) BOOL runningBackgroundTask;
@property NSUInteger busyStarts;
@property NSUInteger busyFinishes;
@end

@implementation BPSheetDelegateRecorder
- (void)setRunningBackgroundTask:(BOOL)runningBackgroundTask
{
	_runningBackgroundTask = runningBackgroundTask;
	if (runningBackgroundTask) self.busyStarts++;
	else self.busyFinishes++;
}
@end

@interface BPSheetApplicationRecorder : NSObject
@property (strong) BPSheetDelegateRecorder *delegate;
@property (strong) NSWindow *mainWindow;
@property (strong) NSMutableArray<NSString *> *events;
@end
@implementation BPSheetApplicationRecorder
@end

@interface BPInertInstallationWindowController : BPInstallationWindowController
@property (strong) BPSheetWindowRecorder *recordedWindow;
@property (strong) NSWindow *parentAtExecution;
@property BOOL busyAtExecution;
@property NSUInteger executions;
@end

@implementation BPInertInstallationWindowController
+ (BPAppDelegate *)applicationDelegate
{
	return (BPAppDelegate *)[(BPSheetApplicationRecorder *)NSApp delegate];
}
- (instancetype)initWithWindowNibName:(NSNibName)windowNibName
{
	if ((self = [super initWithWindow:nil])) {
		_recordedWindow = [BPSheetWindowRecorder new];
	}
	return self;
}
- (NSWindow *)window { return (NSWindow *)self.recordedWindow; }
- (void)executeInstallation
{
	self.executions++;
	self.parentAtExecution = self.window.sheetParent;
	BPSheetApplicationRecorder *application = (BPSheetApplicationRecorder *)NSApp;
	self.busyAtExecution = application.delegate.runningBackgroundTask;
	[application.events addObject:@"execute"];
	[self setValue:@YES forKey:@"operationStatus"];
}
@end

@interface BPInstallationWindowControllerTests : XCTestCase
@property (strong) NSApplication *previousApplication;
@property (strong) BPSheetApplicationRecorder *application;
@property (strong) BPSheetWindowRecorder *parent;
@end

@implementation BPInstallationWindowControllerTests
- (void)setUp
{
	[super setUp];
	self.previousApplication = NSApp;
	self.application = [BPSheetApplicationRecorder new];
	self.application.delegate = [BPSheetDelegateRecorder new];
	self.application.events = [NSMutableArray array];
	self.parent = [BPSheetWindowRecorder new];
	self.parent.events = self.application.events;
	self.application.delegate.window = (NSWindow *)self.parent;
	// Restore this process-local global in tearDown. No method swizzling or
	// real NSApplication construction is needed for the recording app.
	NSApp = (NSApplication *)self.application;
}
- (void)tearDown
{
	self.parent.sheetCompletion = nil;
	self.parent.presentedSheet = nil;
	NSApp = self.previousApplication;
	self.application = nil;
	self.parent = nil;
	[super tearDown];
}

- (void)testStartAttachesDelegateWindowBeforeExecutingWhenMainWindowIsNil
{
	XCTAssertNil(NSApp.mainWindow);
	XCTAssertEqual((id)NSApp.delegate, self.application.delegate);
	XCTAssertNotNil(self.application.delegate.window);
	__block NSUInteger completions = 0;
	BPInertInstallationWindowController *controller = (BPInertInstallationWindowController *)
		[BPInertInstallationWindowController runWithOperation:kBPWindowOperationUpgrade formulae:@[] options:nil completion:^(BOOL success) {
			XCTAssertTrue(success);
			completions++;
		}];
	XCTAssertEqual(controller.executions, 1u);
	XCTAssertTrue(controller.busyAtExecution);
	XCTAssertEqual(controller.parentAtExecution, (NSWindow *)self.parent);
	XCTAssertEqual(controller.window.sheetParent, (NSWindow *)self.parent);
	XCTAssertEqual(self.parent.beginCount, 1u);
	XCTAssertEqualObjects(self.application.events, (@[@"begin", @"execute"]));
	XCTAssertEqual(self.application.delegate.busyStarts, 1u);
	XCTAssertEqual(self.application.delegate.busyFinishes, 0u);
	XCTAssertEqual(completions, 0u);
	[controller okAction:nil];
	XCTAssertFalse(self.application.delegate.runningBackgroundTask);
	XCTAssertEqual(completions, 1u);
}

- (void)testOKDismissesOriginalParentAndCompletesOnceWhenMainWindowIsNil
{
	[self assertDismissalUsesOriginalParentWithMainWindow:nil];
}

- (void)testOKDismissesOriginalParentAndCompletesOnceWhenMainWindowChanges
{
	[self assertDismissalUsesOriginalParentWithMainWindow:[BPSheetWindowRecorder new]];
}

- (void)assertDismissalUsesOriginalParentWithMainWindow:(BPSheetWindowRecorder *)laterWindow
{
	self.application.mainWindow = (NSWindow *)self.parent;
	__block NSUInteger completions = 0;
	BPInertInstallationWindowController *controller = (BPInertInstallationWindowController *)
		[BPInertInstallationWindowController runWithOperation:kBPWindowOperationUpgrade formulae:@[] options:nil completion:^(BOOL success) {
			XCTAssertTrue(success);
			XCTAssertFalse(self.application.delegate.runningBackgroundTask);
			completions++;
		}];
	XCTAssertEqual(controller.window.sheetParent, (NSWindow *)self.parent);
	self.application.mainWindow = (NSWindow *)laterWindow;
	self.application.delegate.window = (NSWindow *)laterWindow;
	XCTAssertEqual(NSApp.mainWindow, (NSWindow *)laterWindow);
	[controller okAction:nil];
	[controller okAction:nil];
	XCTAssertEqual(self.parent.endCount, 1u);
	XCTAssertEqual(laterWindow.endCount, 0u);
	XCTAssertNil(controller.window.sheetParent);
	XCTAssertFalse(self.application.delegate.runningBackgroundTask);
	XCTAssertEqual(self.application.delegate.busyFinishes, 1u);
	XCTAssertEqual(completions, 1u);
}
@end
