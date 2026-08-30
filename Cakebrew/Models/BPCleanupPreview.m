//
//	BPCleanupPreview.m
//	Cakebrew – The Homebrew GUI App for OS X
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

#import "BPCleanupPreview.h"

static NSString * const kBPWouldRemovePrefix = @"Would remove: ";

@implementation BPCleanupPreview

+ (instancetype)previewFromOutput:(NSString *)output
{
	BPCleanupPreview *preview = [[self alloc] init];
	preview->_paths = [self pathsFromOutput:output];
	preview->_itemCount = preview->_paths.count;
	preview->_reclaimableBytes = [self reclaimableBytesFromOutput:output];
	return preview;
}

+ (NSArray<NSString *> *)pathsFromOutput:(NSString *)output
{
	if (output.length == 0)
	{
		return @[];
	}

	NSMutableArray<NSString *> *paths = [NSMutableArray array];

	[output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		// brew streams warnings, progress and prune summaries into the same
		// output. Only the removal lines are removals.
		if (![line hasPrefix:kBPWouldRemovePrefix])
		{
			return;
		}

		NSString *path = [[line substringFromIndex:kBPWouldRemovePrefix.length]
						  stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		path = [self pathByStrippingSizeSuffix:path];

		if (path.length > 0)
		{
			[paths addObject:path];
		}
	}];

	return [paths copy];
}

/// Removes the trailing "(1.5MB)" or "(1,234 files, 45.6MB)" brew appends.
/// Split from the right so a path that itself contains parentheses survives.
+ (NSString *)pathByStrippingSizeSuffix:(NSString *)path
{
	if (![path hasSuffix:@")"])
	{
		return path;
	}

	NSRange open = [path rangeOfString:@" (" options:NSBackwardsSearch];

	if (open.location == NSNotFound)
	{
		return path;
	}

	return [path substringToIndex:open.location];
}

/// Reads brew's own total rather than summing the per-item sizes: brew omits a
/// size for anything it cannot measure, so summing would silently under-report.
+ (unsigned long long)reclaimableBytesFromOutput:(NSString *)output
{
	if (output.length == 0)
	{
		return 0;
	}

	static NSRegularExpression *expression = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		expression = [NSRegularExpression regularExpressionWithPattern:
					  @"would free approximately ([0-9]+(?:\\.[0-9]+)?)\\s*(TB|GB|MB|KB|B)\\b"
															   options:NSRegularExpressionCaseInsensitive
																 error:NULL];
	});

	NSTextCheckingResult *match = [expression firstMatchInString:output
														options:0
														  range:NSMakeRange(0, output.length)];

	if (!match)
	{
		return 0;
	}

	// Brew's disk_usage_readable is 1024-based, so its "MB" is a mebibyte.
	// Parsing with a POSIX locale keeps a comma-decimal locale from reading
	// "49.2" as 492.
	NSString *number = [output substringWithRange:[match rangeAtIndex:1]];
	NSString *unit = [[output substringWithRange:[match rangeAtIndex:2]] uppercaseString];

	NSDecimalNumber *value = [NSDecimalNumber decimalNumberWithString:number
															  locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];

	if ([value isEqual:[NSDecimalNumber notANumber]])
	{
		return 0;
	}

	unsigned long long multiplier = 1;

	if ([unit isEqualToString:@"KB"])      multiplier = 1024ull;
	else if ([unit isEqualToString:@"MB"]) multiplier = 1024ull * 1024;
	else if ([unit isEqualToString:@"GB"]) multiplier = 1024ull * 1024 * 1024;
	else if ([unit isEqualToString:@"TB"]) multiplier = 1024ull * 1024 * 1024 * 1024;

	return (unsigned long long)([value doubleValue] * (double)multiplier);
}

- (BOOL)isEmpty
{
	return self.itemCount == 0 && self.reclaimableBytes == 0;
}

@end
