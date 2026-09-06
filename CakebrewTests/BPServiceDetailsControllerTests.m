#import <XCTest/XCTest.h>
#import "BPServicesViewController.h"
#import "BPServiceDetails.h"
#import "BPService.h"

@interface BPServicesViewController (DetailsTesting)
@property (strong) NSArray<BPService *> *services;
@property (strong) NSTableView *tableView;
@property (strong) BPServiceDetails *details;
@property (strong) NSTextView *detailsText;
@property (strong) NSButton *revealButton;
@property (strong) NSButton *logsButton;
@property (strong) NSButton *outputCopyButton;
- (void)fetchDetailsForName:(NSString *)name completion:(void (^)(BPServiceDetails *))completion;
- (void)fetchServicesWithCompletion:(void (^)(NSArray<BPService *> *))completion;
- (void)openLogURLs:(NSArray<NSURL *> *)urls;
- (void)revealValidatedFileURL:(NSURL *)url;
- (void)openServiceLogs:(id)sender;
- (void)revealServiceFile:(id)sender;
- (void)tableViewSelectionDidChange:(NSNotification *)notification;
- (void)invalidateServiceDetails;
@end

@interface BPDeferredServicesController : BPServicesViewController
@property (strong) NSMutableArray *completions;
@property (copy) void (^listCompletion)(NSArray *);
@property (copy) NSArray *openedURLs;
@property (strong) NSURL *revealedURL;
@end
@implementation BPDeferredServicesController
- (void)fetchDetailsForName:(NSString *)name completion:(void (^)(BPServiceDetails *))completion
{
	[self.completions addObject:[completion copy]];
}
- (void)fetchServicesWithCompletion:(void (^)(NSArray<BPService *> *))completion { self.listCompletion = completion; }
- (void)openLogURLs:(NSArray<NSURL *> *)urls { self.openedURLs = urls; }
- (void)revealValidatedFileURL:(NSURL *)url { self.revealedURL = url; }
@end

@interface BPServiceDetailsControllerTests : XCTestCase
@end
@implementation BPServiceDetailsControllerTests
- (void)testRefreshReloadsDetailsWhenTheSelectedRowDoesNotChange
{
	BPDeferredServicesController *controller = [self controller];
	[self select:0 controller:controller];
	[controller refreshServices];
	controller.listCompletion(controller.services);
	XCTAssertEqual(controller.completions.count, 2u);
}
- (void)testFailurePreservesListAndCompleteRawDiagnostic
{
	BPDeferredServicesController *controller = [self controller];
	NSArray *services = controller.services;
	[self select:0 controller:controller];
	void (^completion)(BPServiceDetails *) = controller.completions.lastObject;
	NSString *raw = [@"Error: diagnostic\n" stringByPaddingToLength:4000 withString:@"full transcript\n" startingAtIndex:0];
	completion([BPServiceDetails detailsForName:@"a" output:raw succeeded:NO]);
	XCTAssertEqual(controller.services, services);
	XCTAssertEqual([controller.tableView numberOfRows], 2);
	XCTAssertTrue([controller.detailsText.string containsString:raw]);
	NSString *visibleFailure = [NSString stringWithFormat:@"%@\n%@", NSLocalizedString(@"Services_Details_Failed", nil), raw];
	XCTAssertTrue([controller.detailsText.string hasPrefix:visibleFailure], @"Failure and raw diagnostic must lead the initial viewport, before metadata placeholders.");
	XCTAssertTrue(controller.outputCopyButton.enabled);
	XCTAssertFalse(controller.logsButton.enabled);
	XCTAssertFalse(controller.revealButton.enabled);
}
- (void)testRefreshAndLeavingRejectBothOldDetailsAndOldListReplies
{
	BPDeferredServicesController *controller = [self controller];
	NSArray *services = controller.services;
	[self select:0 controller:controller];
	void (^detailsReply)(BPServiceDetails *) = controller.completions.lastObject;
	[controller refreshServices];
	detailsReply([self details:@"a"]);
	XCTAssertNil(controller.details);
	[controller invalidateServiceDetails];
	controller.listCompletion(@[]);
	XCTAssertEqual(controller.services, services);
}
- (void)testFileActionsDeduplicateAndRevalidateAtClickTime
{
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
	NSFileManager *files = NSFileManager.defaultManager;
	XCTAssertTrue([files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
	NSString *path = [directory stringByAppendingPathComponent:@"fixture.log"];
	XCTAssertTrue([@"fixture" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
	BPDeferredServicesController *controller = [self controller];
	[self select:0 controller:controller];
	void (^completion)(BPServiceDetails *) = controller.completions.lastObject;
	NSData *data = [NSJSONSerialization dataWithJSONObject:@[@{@"name": @"a", @"file": @"/missing/file", @"loaded_file": path, @"log_path": path, @"error_log_path": path}] options:0 error:nil];
	completion([BPServiceDetails detailsForName:@"a" output:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] succeeded:YES]);
	XCTAssertTrue(controller.logsButton.enabled);
	XCTAssertTrue(controller.revealButton.enabled);
	[controller openServiceLogs:nil];
	[controller revealServiceFile:nil];
	XCTAssertEqual(controller.openedURLs.count, 1u);
	XCTAssertEqualObjects(controller.revealedURL.path, path.stringByResolvingSymlinksInPath);
	controller.openedURLs = nil;
	controller.revealedURL = nil;
	XCTAssertTrue([files removeItemAtPath:path error:nil]);
	[controller openServiceLogs:nil];
	[controller revealServiceFile:nil];
	XCTAssertNil(controller.openedURLs);
	XCTAssertNil(controller.revealedURL);
	XCTAssertFalse(controller.logsButton.enabled);
	XCTAssertFalse(controller.revealButton.enabled);
	XCTAssertTrue([files removeItemAtPath:directory error:nil]);
}
- (BPDeferredServicesController *)controller
{
	BPDeferredServicesController *controller = [BPDeferredServicesController new];
	controller.completions = [NSMutableArray array];
	(void)controller.view;
	controller.services = [BPService servicesFromJSONString:@"[{\"name\":\"a\",\"status\":\"started\"},{\"name\":\"b\",\"status\":\"none\"}]"];
	[controller.tableView reloadData];
	return controller;
}
- (void)select:(NSInteger)row controller:(BPDeferredServicesController *)controller
{
	[controller.tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
}
- (BPServiceDetails *)details:(NSString *)name
{
	return [BPServiceDetails detailsForName:name output:[NSString stringWithFormat:@"[{\"name\":\"%@\"}]", name] succeeded:YES];
}
- (void)testLateAResponseCannotReplaceBOrNewASelection
{
	BPDeferredServicesController *controller = [self controller];
	[self select:0 controller:controller];
	[self select:1 controller:controller];
	XCTAssertEqual(controller.completions.count, 2u);
	if (controller.completions.count != 2) return;
	void (^oldA)(BPServiceDetails *) = controller.completions[0];
	void (^b)(BPServiceDetails *) = controller.completions[1];
	BPServiceDetails *bDetails = [self details:@"b"];
	b(bDetails);
	oldA([self details:@"a"]);
	XCTAssertEqual(controller.details, bDetails);
	[self select:0 controller:controller];
	oldA([self details:@"a"]);
	XCTAssertNil(controller.details);
	void (^newA)(BPServiceDetails *) = controller.completions.lastObject;
	BPServiceDetails *aDetails = [self details:@"a"];
	newA(aDetails);
	XCTAssertEqual(controller.details, aDetails);
}
- (void)testInvalidationAndDeselectRejectPendingResultsWithoutReplacingList
{
	BPDeferredServicesController *controller = [self controller];
	NSArray *services = controller.services;
	[self select:0 controller:controller];
	XCTAssertEqual(controller.completions.count, 1u);
	if (!controller.completions.count) return;
	void (^completion)(BPServiceDetails *) = controller.completions.lastObject;
	[controller invalidateServiceDetails];
	completion([self details:@"a"]);
	XCTAssertNil(controller.details);
	[controller.tableView deselectAll:nil];
	completion([self details:@"a"]);
	XCTAssertNil(controller.details);
	XCTAssertEqual(controller.services, services);
}
@end
