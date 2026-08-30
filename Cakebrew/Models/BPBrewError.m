//
//  BPBrewError.m
//  Cakebrew
//

#import "BPBrewError.h"

NSString *const BPErrorDomain = @"com.brunophilipe.Cakebrew.ErrorDomain";
NSString *const BPBrewErrorExitStatusKey = @"BPBrewErrorExitStatus";

/// Enough of the tail to show what went wrong without filling the screen.
static const NSUInteger kMaximumReportedLines = 12;
static const NSUInteger kMaximumReportedLength = 1500;

@implementation BPBrewError

+ (NSString *)tailOfOutput:(NSString *)output
{
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	[output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		if ([line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].length > 0)
		{
			[lines addObject:line];
		}
	}];

	if (lines.count > kMaximumReportedLines)
	{
		[lines removeObjectsInRange:NSMakeRange(0, lines.count - kMaximumReportedLines)];
	}

	NSString *tail = [lines componentsJoinedByString:@"\n"];
	if (tail.length > kMaximumReportedLength)
	{
		tail = [tail substringFromIndex:tail.length - kMaximumReportedLength];
	}
	return tail;
}

+ (NSError *)errorForExitStatus:(int)status output:(NSString *)output
{
	if (status == 0)
	{
		return nil;
	}

	// BPTask returns -1 when the process could not be launched, which is a
	// different problem from brew rejecting the command.
	BPBrewErrorCode code = (status < 0) ? BPBrewErrorLaunchFailed : BPBrewErrorNonZeroExit;

	NSString *tail = [self tailOfOutput:output ?: @""];
	NSString *description;
	if (tail.length > 0)
	{
		// brew's own words: paraphrasing loses the actionable part.
		description = tail;
	}
	else
	{
		description = [NSString stringWithFormat:NSLocalizedString(@"Error_Brew_Failed_No_Output", nil), status];
	}

	return [NSError errorWithDomain:BPErrorDomain
							   code:code
						   userInfo:@{ NSLocalizedDescriptionKey: description,
									   BPBrewErrorExitStatusKey: @(status) }];
}

@end
