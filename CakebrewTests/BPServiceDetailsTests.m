#import <XCTest/XCTest.h>
#import "BPServiceDetails.h"
#import "BPService.h"
#import "BPHomebrewInterface.h"
#import "BPTask.h"
#import <objc/runtime.h>

@interface BPHomebrewInterface (ServiceDetailsTesting)
- (instancetype)initUniqueInstance;
- (BOOL)performAsyncBrewCommandWithArguments:(NSArray *)arguments wrapsSynchronousRequest:(BOOL)sync includesCompletionMessage:(BOOL)footer dataReturnBlock:(void (^)(NSString *))block;
@end

@interface BPServiceInfoFixtureInterface : BPHomebrewInterface
@property (copy) NSArray *arguments;
@property (copy) NSString *fixture;
@property BOOL succeeded;
@property BOOL readOnly;
@property BOOL footer;
@end
@implementation BPServiceInfoFixtureInterface
+ (id)allocWithZone:(NSZone *)zone { return class_createInstance(self, 0); }
- (BOOL)performAsyncBrewCommandWithArguments:(NSArray *)arguments wrapsSynchronousRequest:(BOOL)sync includesCompletionMessage:(BOOL)footer dataReturnBlock:(void (^)(NSString *))block
{
	self.arguments = arguments;
	self.readOnly = sync;
	self.footer = footer;
	block(self.fixture);
	return self.succeeded;
}
@end

@interface BPServiceInfoShellInterface : BPHomebrewInterface
@property (copy) NSString *fixtureCommand;
@end
@implementation BPServiceInfoShellInterface
+ (id)allocWithZone:(NSZone *)zone { return class_createInstance(self, 0); }
- (NSArray *)formatArguments:(NSArray *)arguments sendOutputId:(BOOL)marker
{
	return @[@"-c", self.fixtureCommand];
}
@end

@interface BPServiceDetailsTests : XCTestCase
@end

@implementation BPServiceDetailsTests
- (void)testRealServiceListUsesCleanJSONAndRejectsFailedPartialOutput
{
	BPServiceInfoShellInterface *interface = [[BPServiceInfoShellInterface allocWithZone:NULL] initUniqueInstance];
	interface.brewTransport = kBPBrewTransportDirect;
	[interface setValue:@"/bin/sh" forKey:@"path_shell"];
	interface.fixtureCommand = @"printf 'banner\\n+++++Cakebrew+++++\\n[{\"name\":\"redis\",\"status\":\"started\"}]\\n'";
	XCTAssertEqualObjects([interface listServices].firstObject.name, @"redis");
	interface.fixtureCommand = @"printf '+++++Cakebrew+++++\\n[{\"name\":\"redis\"}]\\n'; exit 7";
	XCTAssertEqual([interface listServices].count, 0u);
}
- (void)testLoadedFileIsRetainedSeparatelyFromFormulaServiceFile
{
	BPServiceDetails *result = [BPServiceDetails detailsForName:@"redis" output:@"[{\"name\":\"redis\",\"file\":\"/opt/redis.plist\",\"loaded_file\":\"~/Library/LaunchAgents/redis.plist\"}]" succeeded:YES];
	XCTAssertEqualObjects(result.serviceFile, @"/opt/redis.plist");
	XCTAssertEqualObjects(result.loadedFile, @"~/Library/LaunchAgents/redis.plist");
}
- (void)testRealTaskKeepsJSONCleanPreservesStatusAndDoesNotReplaceCancelTarget
{
	BPServiceInfoShellInterface *interface = [[BPServiceInfoShellInterface allocWithZone:NULL] initUniqueInstance];
	interface.brewTransport = kBPBrewTransportDirect;
	[interface setValue:@"/bin/sh" forKey:@"path_shell"];
	BPTask *existing = [[BPTask alloc] initWithPath:@"/usr/bin/true" arguments:@[]];
	[interface setValue:existing forKey:@"currentOperationTask"];
	interface.fixtureCommand = @"printf 'login banner\\n+++++Cakebrew+++++\\n[{\"name\":\"redis\"}]\\n'";
	BPServiceDetails *result = [interface serviceDetailsForName:@"redis"];
	XCTAssertTrue(result.available);
	XCTAssertEqualObjects(result.rawOutput, @"[{\"name\":\"redis\"}]\n");
	XCTAssertEqual([interface valueForKey:@"currentOperationTask"], existing);
	interface.fixtureCommand = @"printf '+++++Cakebrew+++++\\nError: fixture failure\\n'; exit 7";
	result = [interface serviceDetailsForName:@"redis"];
	XCTAssertFalse(result.available);
	XCTAssertEqualObjects(result.rawOutput, @"Error: fixture failure\n");
	XCTAssertEqual([interface valueForKey:@"currentOperationTask"], existing);
}
- (void)testUnsupportedHelperTransportCannotDispatchOrHijackAnOperation
{
	BPServiceInfoFixtureInterface *interface = [[BPServiceInfoFixtureInterface allocWithZone:NULL] initUniqueInstance];
	interface.brewTransport = kBPBrewTransportHelper;
	interface.fixture = @"[{\"name\":\"redis\"}]";
	interface.succeeded = YES;
	BPServiceDetails *result = [interface serviceDetailsForName:@"redis"];
	XCTAssertFalse(result.available);
	XCTAssertGreaterThan(result.rawOutput.length, 0u);
	XCTAssertNil(interface.arguments);
}
- (void)testMockOwnsTheReadOnlyServiceDetailBoundary
{
	Class mock = NSClassFromString(@"BPMockHomebrewInterface");
	Method real = class_getInstanceMethod(BPHomebrewInterface.class, @selector(serviceDetailsForName:));
	Method replacement = class_getInstanceMethod(mock, @selector(serviceDetailsForName:));
	XCTAssertNotEqual(method_getImplementation(real), method_getImplementation(replacement));
}
- (void)testReadOnlyTransportPreservesFailureAndRequestsCleanOutput
{
	BPServiceInfoFixtureInterface *interface = [[BPServiceInfoFixtureInterface allocWithZone:NULL] initUniqueInstance];
	interface.fixture = @"[{\"name\":\"redis\"}]";
	interface.succeeded = YES;
	XCTAssertTrue([interface serviceDetailsForName:@"redis"].available);
	XCTAssertEqualObjects(interface.arguments, (@[@"services", @"info", @"--json", @"redis"]));
	XCTAssertTrue(interface.readOnly);
	XCTAssertFalse(interface.footer);
	interface.succeeded = NO;
	interface.fixture = @"Error: unavailable\nfull diagnostic";
	BPServiceDetails *result = [interface serviceDetailsForName:@"redis"];
	XCTAssertFalse(result.available);
	XCTAssertEqualObjects(result.rawOutput, interface.fixture);
}
- (void)testFailuresRetainRawOutputAndDoNotAcceptAnotherService
{
	for (NSString *output in @[@"Error: unavailable", @"[]", @"{}", @"[null]", @"[{\"name\":\"other\"}]", @"[{\"name\":\"redis\"},{\"name\":\"redis\"}]"]) {
		BPServiceDetails *result = [BPServiceDetails detailsForName:@"redis" output:output succeeded:YES];
		XCTAssertFalse(result.available);
		XCTAssertEqualObjects(result.rawOutput, output);
	}
	XCTAssertFalse([BPServiceDetails detailsForName:@"redis" output:@"[{\"name\":\"redis\"}]" succeeded:NO].available);
}
- (void)testMissingAndWrongTypedMetadataRemainUnavailable
{
	for (NSString *pid in @[@"null", @"true", @"0", @"-1", @"1.5", @"\"123\""]) {
		NSString *json = [NSString stringWithFormat:@"[{\"name\":\"redis\",\"pid\":%@,\"user\":null,\"file\":3,\"log_path\":[],\"error_log_path\":null,\"exit_code\":true,\"unknown\":{}}]", pid];
		BPServiceDetails *result = [BPServiceDetails detailsForName:@"redis" output:json succeeded:YES];
		XCTAssertTrue(result.available);
		XCTAssertNil(result.service.pid);
		XCTAssertNil(result.service.user);
		XCTAssertNil(result.serviceFile);
		XCTAssertNil(result.logPath);
		XCTAssertNil(result.errorLogPath);
		XCTAssertNil(result.exitCode);
	}
}
- (void)testLocalFileValidationRejectsUnsafePathsAndRevalidatesDeletedFiles
{
	NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
	NSFileManager *files = NSFileManager.defaultManager;
	XCTAssertTrue([files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil]);
	NSString *path = [directory stringByAppendingPathComponent:@"service log.txt"];
	XCTAssertTrue([@"fixture" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil]);
	XCTAssertEqualObjects([BPServiceDetails readableFileURLForPath:path].path, path.stringByResolvingSymlinksInPath);
	NSString *link = [directory stringByAppendingPathComponent:@"link"];
	XCTAssertTrue([files createSymbolicLinkAtPath:link withDestinationPath:path error:nil]);
	XCTAssertEqualObjects([BPServiceDetails readableFileURLForPath:link].path, path.stringByResolvingSymlinksInPath);
	for (NSString *invalid in @[@"", @"relative.log", @"file:///etc/hosts", @"https://example.com/log", @"//server/share", @"~another/log", @"/dev/null", @"/tmp", @"/etc/hosts\n"]) {
		XCTAssertNil([BPServiceDetails readableFileURLForPath:invalid], @"%@", invalid);
	}
	XCTAssertTrue([files removeItemAtPath:path error:nil]);
	XCTAssertNil([BPServiceDetails readableFileURLForPath:path]);
	XCTAssertNil([BPServiceDetails readableFileURLForPath:link]);
	XCTAssertTrue([files removeItemAtPath:directory error:nil]);
}
- (void)testParsesSelectedServiceMetadata
{
	NSString *json = @"[{\"name\":\"redis\",\"status\":\"started\",\"pid\":123,\"user\":\"mockuser\",\"file\":\"/tmp/service.plist\",\"log_path\":\"/tmp/service.log\",\"error_log_path\":\"/tmp/service.log\",\"exit_code\":0}]";
	BPServiceDetails *details = [BPServiceDetails detailsForName:@"redis" output:json succeeded:YES];
	XCTAssertTrue(details.available);
	XCTAssertEqualObjects(details.service.name, @"redis");
	XCTAssertEqualObjects(details.service.pid, @123);
	XCTAssertEqualObjects(details.service.user, @"mockuser");
	XCTAssertEqualObjects(details.serviceFile, @"/tmp/service.plist");
	XCTAssertEqualObjects(details.logPath, @"/tmp/service.log");
	XCTAssertEqualObjects(details.errorLogPath, details.logPath);
	XCTAssertEqualObjects(details.exitCode, @0);
	XCTAssertEqualObjects(details.rawOutput, json);
}
@end
