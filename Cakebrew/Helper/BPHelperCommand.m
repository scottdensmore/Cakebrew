//
//  BPHelperCommand.m
//  Cakebrew
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.	If not, see <http://www.gnu.org/licenses/>.
//

#import "BPHelperCommand.h"

@implementation BPHelperCommand

+ (NSArray<NSString *> *)shellArgumentsForBrewArguments:(NSArray<NSString *> *)arguments
										   outputMarker:(NSString *)marker
{
	NSMutableArray<NSString *> *argv;

	if (marker.length > 0)
	{
		// $1 is the marker; shift drops it so "$@" is exactly brew's arguments.
		// Printing it via a positional parameter keeps the command string fixed
		// even if the marker ever contained shell metacharacters.
		argv = [NSMutableArray arrayWithArray:@[ @"-l", @"-c",
												 @"printf '%s\\n' \"$1\"; shift; brew \"$@\"",
												 @"brew", marker ]];
	}
	else
	{
		argv = [NSMutableArray arrayWithArray:@[ @"-l", @"-c", @"brew \"$@\"", @"brew" ]];
	}

	[argv addObjectsFromArray:(arguments ?: @[])];
	return argv;
}

@end
