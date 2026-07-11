//
//  BPPreferences.m
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

#import "BPPreferences.h"

NSString *const kBPBackgroundCheckEnabledKey = @"BPBackgroundCheckEnabled";
NSString *const kBPBackgroundCheckIntervalKey = @"BPBackgroundCheckInterval";
NSString *const kBPGreedyCaskUpgradesKey = @"BPGreedyCaskUpgrades";

@implementation BPPreferences

+ (void)registerDefaults
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kBPBackgroundCheckEnabledKey: @YES,
		kBPBackgroundCheckIntervalKey: @(21600.0), // 6 hours
		kBPGreedyCaskUpgradesKey: @NO,
	}];
}

+ (BOOL)backgroundCheckEnabled
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:kBPBackgroundCheckEnabledKey];
}

+ (void)setBackgroundCheckEnabled:(BOOL)enabled
{
	[[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kBPBackgroundCheckEnabledKey];
}

+ (NSTimeInterval)backgroundCheckInterval
{
	return [[NSUserDefaults standardUserDefaults] doubleForKey:kBPBackgroundCheckIntervalKey];
}

+ (void)setBackgroundCheckInterval:(NSTimeInterval)interval
{
	[[NSUserDefaults standardUserDefaults] setDouble:interval forKey:kBPBackgroundCheckIntervalKey];
}

+ (BOOL)greedyCaskUpgrades
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:kBPGreedyCaskUpgradesKey];
}

+ (void)setGreedyCaskUpgrades:(BOOL)greedy
{
	[[NSUserDefaults standardUserDefaults] setBool:greedy forKey:kBPGreedyCaskUpgradesKey];
}

@end
