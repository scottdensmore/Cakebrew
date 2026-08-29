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
NSString *const kBPLastSelectedSidebarRowKey = @"BPLastSelectedSidebarRow";
NSString *const kBPSortColumnIdentifierKey = @"BPSortColumnIdentifier";
NSString *const kBPSortAscendingKey = @"BPSortAscending";

@implementation BPPreferences

+ (void)registerDefaults
{
	[[NSUserDefaults standardUserDefaults] registerDefaults:@{
		kBPBackgroundCheckEnabledKey: @YES,
		kBPBackgroundCheckIntervalKey: @(21600.0), // 6 hours
		kBPGreedyCaskUpgradesKey: @NO,
		// 1 == FormulaeSideBarItemInstalled, where the app has always opened.
		kBPLastSelectedSidebarRowKey: @1,
		kBPSortAscendingKey: @YES,
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

+ (NSInteger)lastSelectedSidebarRow
{
	return [[NSUserDefaults standardUserDefaults] integerForKey:kBPLastSelectedSidebarRowKey];
}

+ (void)setLastSelectedSidebarRow:(NSInteger)row
{
	[[NSUserDefaults standardUserDefaults] setInteger:row forKey:kBPLastSelectedSidebarRowKey];
}

+ (NSString *)sortColumnIdentifier
{
	return [[NSUserDefaults standardUserDefaults] stringForKey:kBPSortColumnIdentifierKey];
}

+ (void)setSortColumnIdentifier:(NSString *)identifier
{
	if (identifier.length == 0)
	{
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:kBPSortColumnIdentifierKey];
		return;
	}
	[[NSUserDefaults standardUserDefaults] setObject:identifier forKey:kBPSortColumnIdentifierKey];
}

+ (BOOL)sortAscending
{
	return [[NSUserDefaults standardUserDefaults] boolForKey:kBPSortAscendingKey];
}

+ (void)setSortAscending:(BOOL)ascending
{
	[[NSUserDefaults standardUserDefaults] setBool:ascending forKey:kBPSortAscendingKey];
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
