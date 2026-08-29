//
//  BPXibAppearanceTests.m
//  CakebrewTests
//
//  Xibs that pin absolute colors don't adapt to appearance. The Export/Import
//  window pinned its log view and clip view to pure white, so in Dark Mode the
//  brew output was a blinding white rectangle inside a dark window, and three
//  labels were pinned to a fixed ~34% gray that is near-invisible against the
//  dark control background.
//
//  Semantic colors (textBackgroundColor, secondaryLabelColor, …) adapt on their
//  own, so the rule is simply that no absolute color may appear in a Base.lproj
//  xib. This scans the xib sources rather than the compiled nibs — __FILE__ is
//  the compile-time path of this file, which is inside the checkout on both a
//  dev machine and CI.
//

#import <XCTest/XCTest.h>

@interface BPXibAppearanceTests : XCTestCase
@end

@implementation BPXibAppearanceTests

- (NSString *)baseLprojPath
{
	NSString *repoRoot = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	return [repoRoot stringByAppendingPathComponent:@"Cakebrew/Base.lproj"];
}

- (NSArray<NSString *> *)xibPaths
{
	NSString *dir = [self baseLprojPath];
	NSArray *entries = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:dir error:NULL];
	XCTAssertGreaterThan(entries.count, 0u, @"could not locate Base.lproj at %@", dir);

	NSMutableArray *paths = [NSMutableArray array];
	for (NSString *entry in entries)
	{
		if ([entry.pathExtension isEqualToString:@"xib"])
		{
			[paths addObject:[dir stringByAppendingPathComponent:entry]];
		}
	}
	XCTAssertGreaterThan(paths.count, 0u, @"no xibs found in %@", dir);
	return paths;
}

/// Every line matching `pattern`, as "file:line  text", for a readable failure.
- (NSArray<NSString *> *)offendingLinesMatching:(NSString *)pattern
{
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
	NSMutableArray<NSString *> *offenders = [NSMutableArray array];

	for (NSString *path in [self xibPaths])
	{
		NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
		__block NSUInteger lineNumber = 0;
		[contents enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
			lineNumber++;
			if ([regex numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)] > 0)
			{
				[offenders addObject:[NSString stringWithFormat:@"%@:%lu  %@",
									  path.lastPathComponent, (unsigned long)lineNumber,
									  [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]];
			}
		}];
	}
	return offenders;
}

- (void)testNoOpaqueWhiteFillsRemain
{
	// A pinned white background stays white in Dark Mode. Fully transparent
	// fills (alpha="0.0") are fine — they paint nothing.
	NSArray *offenders = [self offendingLinesMatching:@"white=\"1\" alpha=\"1\""];

	XCTAssertEqual(offenders.count, 0u,
				   @"opaque white is pinned in:\n%@\nUse a semantic color such as textBackgroundColor.",
				   [offenders componentsJoinedByString:@"\n"]);
}

- (void)testNoAbsoluteTextColorsRemain
{
	// A fixed gray does not adapt: ~34% gray is readable on a light control
	// background and nearly invisible on a dark one.
	NSArray *offenders = [self offendingLinesMatching:@"key=\"textColor\".*colorSpace=\"calibratedWhite\""];

	XCTAssertEqual(offenders.count, 0u,
				   @"absolute text colors are pinned in:\n%@\nUse secondaryLabelColor or labelColor.",
				   [offenders componentsJoinedByString:@"\n"]);
}

- (void)testTheScanActuallySeesTheXibs
{
	// Guards the guard: if the path walk ever broke, both tests above would
	// pass vacuously by scanning nothing.
	NSArray *paths = [self xibPaths];
	XCTAssertGreaterThanOrEqual(paths.count, 7u, @"expected every Base.lproj xib to be scanned");

	NSArray *anyColour = [self offendingLinesMatching:@"<color key="];
	XCTAssertGreaterThan(anyColour.count, 0u, @"the scan found no colors at all, so it is not reading the xibs");
}

@end
