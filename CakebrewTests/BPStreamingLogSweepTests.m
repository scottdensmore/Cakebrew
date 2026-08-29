//
//  BPStreamingLogSweepTests.m
//  CakebrewTests
//
//  #69 replaced the per-chunk `setString:` rebuild in three streaming log
//  views, but missed a fourth: BPBundleWindowController lives in Cakebrew/
//  rather than Cakebrew/Controllers/, so the sweep that found the others
//  skipped it and it kept blocking the producer thread on the main thread for
//  every chunk of `brew bundle` output.
//
//  A sweep over the whole target is the guard that would have caught it, so
//  that is what this is: no streaming path may rebuild its document.
//

#import <XCTest/XCTest.h>

@interface BPStreamingLogSweepTests : XCTestCase
@end

@implementation BPStreamingLogSweepTests

- (NSString *)sourceRoot
{
	NSString *repoRoot = [[@(__FILE__) stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	return [repoRoot stringByAppendingPathComponent:@"Cakebrew"];
}

/// Every "file:line  text" in the app sources matching `pattern`.
- (NSArray<NSString *> *)occurrencesOf:(NSString *)pattern
{
	NSString *root = [self sourceRoot];
	NSDirectoryEnumerator *walker = [[NSFileManager defaultManager] enumeratorAtPath:root];
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
	NSMutableArray<NSString *> *hits = [NSMutableArray array];
	NSUInteger scanned = 0;

	for (NSString *relative in walker)
	{
		if (![relative.pathExtension isEqualToString:@"m"])
		{
			continue;
		}
		scanned++;
		NSString *path = [root stringByAppendingPathComponent:relative];
		NSString *contents = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
		__block NSUInteger lineNumber = 0;
		[contents enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
			lineNumber++;
			if ([regex numberOfMatchesInString:line options:0 range:NSMakeRange(0, line.length)] > 0)
			{
				[hits addObject:[NSString stringWithFormat:@"%@:%lu  %@", relative, (unsigned long)lineNumber,
								 [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]]];
			}
		}];
	}

	XCTAssertGreaterThan(scanned, 20u, @"the sweep should reach the whole target, not a subdirectory");
	return hits;
}

- (void)testNoStreamingPathRebuildsItsDocumentOnTheMainThread
{
	// The exact shape of the defect: hand the whole accumulated transcript back
	// to the view, synchronously, from the thread producing it.
	NSArray *hits = [self occurrencesOf:@"performSelectorOnMainThread:@selector\\(setString:\\)"];

	XCTAssertEqual(hits.count, 0u,
				   @"a streaming view is rebuilding its document per chunk:\n%@\n"
				   @"Use -[BPAutoScrollTextView appendOutput:] instead.",
				   [hits componentsJoinedByString:@"\n"]);
}

- (void)testNoStreamingPathAppendsToItsOwnStringValue
{
	// The other form the defect took: read the view's whole string, append, set
	// it back — quadratic, and it resets VoiceOver's cursor to the top.
	NSArray *hits = [self occurrencesOf:@"setString:\\[.*\\.string stringByAppendingString:"];

	XCTAssertEqual(hits.count, 0u,
				   @"a streaming view is rebuilding its document per chunk:\n%@",
				   [hits componentsJoinedByString:@"\n"]);
}

@end
