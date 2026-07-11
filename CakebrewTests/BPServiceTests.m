//
//  BPServiceTests.m
//  CakebrewTests
//
//  Tests for BPService: parsing `brew services list --json` output into
//  service objects, defensively (brew's JSON has nulls, and output may not
//  be JSON at all when brew errors).
//

#import <XCTest/XCTest.h>
#import "BPService.h"

@interface BPServiceTests : XCTestCase
@end

@implementation BPServiceTests

- (void)testParsesEmptyArray
{
	// The common case on machines with no services installed.
	XCTAssertEqualObjects([BPService servicesFromJSONString:@"[]"], @[]);
}

- (void)testParsesFullServiceEntry
{
	NSString *json = @"[{\"name\":\"postgresql@14\",\"service_name\":\"homebrew.mxcl.postgresql@14\","
					  @"\"running\":true,\"loaded\":true,\"schedulable\":false,\"pid\":123,"
					  @"\"exit_code\":null,\"user\":\"scott\",\"status\":\"started\","
					  @"\"file\":\"~/Library/LaunchAgents/homebrew.mxcl.postgresql@14.plist\",\"registered\":true}]";

	NSArray<BPService *> *services = [BPService servicesFromJSONString:json];

	XCTAssertEqual(services.count, 1u);
	BPService *service = services.firstObject;
	XCTAssertEqualObjects(service.name, @"postgresql@14");
	XCTAssertEqual(service.status, kBPServiceStatusStarted);
	XCTAssertEqualObjects(service.statusString, @"started");
	XCTAssertEqualObjects(service.user, @"scott");
	XCTAssertEqualObjects(service.pid, @123);
}

- (void)testParsesNullUserAndPid
{
	// Stopped services report user and pid as JSON null.
	NSString *json = @"[{\"name\":\"redis\",\"running\":false,\"pid\":null,\"user\":null,\"status\":\"none\"}]";

	NSArray<BPService *> *services = [BPService servicesFromJSONString:json];

	XCTAssertEqual(services.count, 1u);
	BPService *service = services.firstObject;
	XCTAssertEqualObjects(service.name, @"redis");
	XCTAssertEqual(service.status, kBPServiceStatusNone);
	XCTAssertNil(service.user);
	XCTAssertNil(service.pid);
}

- (void)testStatusMapping
{
	NSDictionary<NSString *, NSNumber *> *cases = @{
		@"started":   @(kBPServiceStatusStarted),
		@"stopped":   @(kBPServiceStatusStopped),
		@"none":      @(kBPServiceStatusNone),
		@"error":     @(kBPServiceStatusError),
		@"scheduled": @(kBPServiceStatusScheduled),
		@"banana":    @(kBPServiceStatusUnknown), // unrecognized -> unknown
	};

	for (NSString *raw in cases) {
		NSString *json = [NSString stringWithFormat:@"[{\"name\":\"svc\",\"status\":\"%@\"}]", raw];
		BPService *service = [BPService servicesFromJSONString:json].firstObject;
		XCTAssertEqual(service.status, cases[raw].integerValue, @"status '%@' should map correctly", raw);
	}
}

- (void)testNonJSONOutputYieldsEmptyList
{
	// brew can print an error message instead of JSON; never crash on it.
	XCTAssertEqualObjects([BPService servicesFromJSONString:@"Error: some brew failure"], @[]);
	XCTAssertEqualObjects([BPService servicesFromJSONString:@""], @[]);
}

- (void)testNonArrayJSONYieldsEmptyList
{
	XCTAssertEqualObjects([BPService servicesFromJSONString:@"{\"name\":\"redis\"}"], @[]);
}

- (void)testEntriesWithoutANameAreSkipped
{
	NSString *json = @"[{\"status\":\"started\"},{\"name\":\"redis\",\"status\":\"none\"}]";

	NSArray<BPService *> *services = [BPService servicesFromJSONString:json];

	XCTAssertEqual(services.count, 1u);
	XCTAssertEqualObjects(services.firstObject.name, @"redis");
}

@end
