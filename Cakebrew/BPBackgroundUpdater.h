//
//  BPBackgroundUpdater.h
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

#import <Foundation/Foundation.h>

/**
 *  Periodically refreshes the Homebrew lists (driven by the BPPreferences
 *  background-check settings) and surfaces the outdated count as a dock
 *  badge plus a notification when new outdated packages appear.
 */
@interface BPBackgroundUpdater : NSObject

/** Starts observing settings and outdated counts, and schedules the timer. */
- (void)start;

/** The dock badge for an outdated count: nil when zero, the number otherwise. */
+ (NSString *)badgeLabelForOutdatedCount:(NSUInteger)count;

/** Whether a rise from previousCount to count warrants a notification. */
+ (BOOL)shouldNotifyForCount:(NSUInteger)count previousCount:(NSUInteger)previousCount;

@end
