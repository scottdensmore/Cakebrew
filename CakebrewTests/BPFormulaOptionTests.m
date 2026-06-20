//
//  BPFormulaOptionTests.m
//  CakebrewTests
//
//  Tests for BPFormulaOption's NSCopying and NSSecureCoding conformance.
//

#import <XCTest/XCTest.h>
#import "BPFormulaOption.h"

@interface BPFormulaOptionTests : XCTestCase
@end

@implementation BPFormulaOptionTests

- (void)testSupportsSecureCoding
{
	XCTAssertTrue([BPFormulaOption supportsSecureCoding]);
}

- (void)testCopyPreservesNameAndExplanation
{
	BPFormulaOption *option = [[BPFormulaOption alloc] init];
	option.name = @"--with-foo";
	option.explanation = @"Build with foo support";

	BPFormulaOption *copy = [option copy];

	XCTAssertNotNil(copy);
	XCTAssertNotEqual(copy, option, @"copy should be a distinct instance");
	XCTAssertEqualObjects(copy.name, @"--with-foo");
	XCTAssertEqualObjects(copy.explanation, @"Build with foo support");
}

- (void)testSecureCodingRoundTrip
{
	BPFormulaOption *option = [[BPFormulaOption alloc] init];
	option.name = @"--HEAD";
	option.explanation = @"Install HEAD version";

	NSError *error = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:option requiringSecureCoding:YES error:&error];
	XCTAssertNil(error);
	XCTAssertNotNil(data);

	BPFormulaOption *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[BPFormulaOption class] fromData:data error:&error];
	XCTAssertNil(error);
	XCTAssertEqualObjects(decoded.name, @"--HEAD");
	XCTAssertEqualObjects(decoded.explanation, @"Install HEAD version");
}

- (void)testSecureCodingPreservesNilFields
{
	// A bare option (no name/explanation) must round-trip without error.
	BPFormulaOption *option = [[BPFormulaOption alloc] init];

	NSError *error = nil;
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:option requiringSecureCoding:YES error:&error];
	XCTAssertNil(error);

	BPFormulaOption *decoded = [NSKeyedUnarchiver unarchivedObjectOfClass:[BPFormulaOption class] fromData:data error:&error];
	XCTAssertNil(error);
	XCTAssertNil(decoded.name);
	XCTAssertNil(decoded.explanation);
}

@end
