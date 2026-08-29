//
//  BPVersionStampingTests.m
//  CakebrewTests
//
//  Version stamping was manual, duplicated and wrong. The app's Info.plist
//  hardcoded its short version while taking the build number from a build
//  setting; the helper's hardcoded *both*, so bumping the project version
//  bumped the app and left the embedded helper pinned — the bundle shipped a
//  helper claiming a different version than its host. The release workflow had
//  no version step at all, so tagging v1.4 published an app that said 1.3.
//
//  Both plists now derive from build settings, and this fails if a literal
//  creeps back in.
//

#import <XCTest/XCTest.h>

@interface BPVersionStampingTests : XCTestCase
@end

@implementation BPVersionStampingTests

- (NSString *)contentsOfRepoFile:(NSString *)relativePath
{
	NSString *repoRoot = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	NSString *path = [repoRoot stringByAppendingPathComponent:relativePath];
	NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
	XCTAssertGreaterThan(contents.length, 0u, @"could not read %@", path);
	return contents;
}

/// The string value following `key` in an Info.plist source file.
- (NSString *)valueForPlistKey:(NSString *)key in:(NSString *)plist
{
	NSString *pattern = [NSString stringWithFormat:@"<key>%@</key>\\s*<string>([^<]*)</string>", key];
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
	NSTextCheckingResult *match = [regex firstMatchInString:plist options:0 range:NSMakeRange(0, plist.length)];
	XCTAssertNotNil(match, @"%@ not found", key);
	return [plist substringWithRange:[match rangeAtIndex:1]];
}

- (void)testTheAppDerivesBothVersionsFromBuildSettings
{
	NSString *plist = [self contentsOfRepoFile:@"Cakebrew/Cakebrew-Info.plist"];

	XCTAssertEqualObjects([self valueForPlistKey:@"CFBundleShortVersionString" in:plist], @"$(MARKETING_VERSION)");
	XCTAssertEqualObjects([self valueForPlistKey:@"CFBundleVersion" in:plist], @"$(CURRENT_PROJECT_VERSION)");
}

- (void)testTheHelperDerivesBothVersionsFromBuildSettings
{
	// The helper is embedded in the app bundle; a literal here is how it ended
	// up shipping a different version than its host.
	NSString *plist = [self contentsOfRepoFile:@"Cakebrew/Helper/CakebrewHelper-Info.plist"];

	XCTAssertEqualObjects([self valueForPlistKey:@"CFBundleShortVersionString" in:plist], @"$(MARKETING_VERSION)");
	XCTAssertEqualObjects([self valueForPlistKey:@"CFBundleVersion" in:plist], @"$(CURRENT_PROJECT_VERSION)");
}

- (void)testEveryTargetDefinesTheVersionSettingsItReferences
{
	// A plist referencing $(MARKETING_VERSION) with no such setting expands to
	// an empty string rather than failing the build.
	NSString *project = [self contentsOfRepoFile:@"Cakebrew.xcodeproj/project.pbxproj"];

	NSUInteger appAndHelperConfigurations = 4;   // Debug + Release, app + helper
	XCTAssertGreaterThanOrEqual([self countOf:@"MARKETING_VERSION = " in:project], appAndHelperConfigurations);
	XCTAssertGreaterThanOrEqual([self countOf:@"CURRENT_PROJECT_VERSION = " in:project], appAndHelperConfigurations);
}

- (void)testTheReleaseWorkflowStampsTheVersionFromTheTag
{
	// Without this the workflow archives whatever the checked-in settings say,
	// so a tagged release can publish the previous version's number.
	NSString *workflow = [self contentsOfRepoFile:@".github/workflows/release.yml"];

	XCTAssertGreaterThan([self countOf:@"MARKETING_VERSION=" in:workflow], 0u,
						 @"the archive step should pass the version parsed from the tag");
	XCTAssertGreaterThan([self countOf:@"CFBundleShortVersionString" in:workflow], 0u,
						 @"the export should be asserted against the tag before publishing");
}

- (NSUInteger)countOf:(NSString *)needle in:(NSString *)haystack
{
	NSUInteger count = 0;
	NSRange search = NSMakeRange(0, haystack.length);
	while (search.length > 0)
	{
		NSRange found = [haystack rangeOfString:needle options:0 range:search];
		if (found.location == NSNotFound) break;
		count++;
		NSUInteger next = NSMaxRange(found);
		search = NSMakeRange(next, haystack.length - next);
	}
	return count;
}

@end
