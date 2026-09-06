#import "BPAutoremovePreview.h"

@implementation BPAutoremovePreview
+ (instancetype)previewWithOutput:(NSString *)output succeeded:(BOOL)succeeded
{
	BPAutoremovePreview *preview = [[self alloc] init];
	preview->_rawOutput = [output copy] ?: @"";
	preview->_names = @[];
	if (!succeeded || !output) return preview;
	NSString *text = [[output stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!text.length) { preview->_valid = YES; return preview; }
	NSArray *lines = [text componentsSeparatedByString:@"\n"];
	NSRegularExpression *header = [NSRegularExpression regularExpressionWithPattern:@"^==> Would autoremove ([1-9][0-9]*) unneeded formula(e)?:$" options:0 error:NULL];
	NSTextCheckingResult *match = [header firstMatchInString:lines[0] options:0 range:NSMakeRange(0, [lines[0] length])];
	if (!match) return preview;
	NSUInteger count = [[lines[0] substringWithRange:[match rangeAtIndex:1]] integerValue];
	if (count != lines.count - 1 || (count == 1) != ([match rangeAtIndex:2].location == NSNotFound)) return preview;
	NSRegularExpression *namePattern = [NSRegularExpression regularExpressionWithPattern:@"^(?:[a-zA-Z0-9][a-zA-Z0-9_.+-]*/[a-zA-Z0-9][a-zA-Z0-9_.+-]*/)?[a-zA-Z0-9][a-zA-Z0-9_.+@-]*$" options:0 error:NULL];
	NSMutableOrderedSet *names = [NSMutableOrderedSet orderedSet];
	for (NSString *name in [lines subarrayWithRange:NSMakeRange(1, count)]) {
		if (![namePattern firstMatchInString:name options:0 range:NSMakeRange(0, name.length)] || [names containsObject:name]) return preview;
		[names addObject:name];
	}
	preview->_names = [names.array copy];
	preview->_valid = YES;
	return preview;
}
@end
