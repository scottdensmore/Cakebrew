//
//	BPBrewfile.m
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

#import "BPBrewfile.h"

static NSString * const kBPBrewfileName = @"Brewfile";

@implementation BPBrewfile

+ (BOOL)isBrewfileURL:(NSURL *)url
{
	if (!url.isFileURL)
	{
		return NO;
	}

	NSString *name = url.lastPathComponent;

	if (name.length == 0)
	{
		return NO;
	}

	// "Brewfile", the canonical name. Case-insensitive because the default
	// filesystem is.
	if ([name caseInsensitiveCompare:kBPBrewfileName] == NSOrderedSame)
	{
		return YES;
	}

	// "work.Brewfile" — brew bundle takes any --file path, and keeping several
	// side by side is common. Anything *after* the name is something else:
	// Brewfile.lock.json is JSON that brew writes, not a bundle description,
	// and offering to install from it would be wrong.
	NSString *suffix = [@"." stringByAppendingString:kBPBrewfileName];

	return name.length > suffix.length
		&& [[name substringFromIndex:name.length - suffix.length] caseInsensitiveCompare:suffix] == NSOrderedSame;
}

+ (NSArray<NSURL *> *)brewfileURLsFrom:(NSArray<NSURL *> *)urls
{
	if (urls.count == 0)
	{
		return @[];
	}

	NSMutableArray<NSURL *> *brewfiles = [NSMutableArray array];

	for (NSURL *url in urls)
	{
		if ([self isBrewfileURL:url])
		{
			[brewfiles addObject:url];
		}
	}

	return [brewfiles copy];
}

@end
