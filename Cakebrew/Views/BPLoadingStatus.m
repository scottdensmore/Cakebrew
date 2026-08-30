//
//	BPLoadingStatus.m
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

#import "BPLoadingStatus.h"

@implementation BPLoadingStatus

+ (NSString *)localizationKeyForListMode:(BPListMode)mode
{
	switch (mode)
	{
		case kBPListInstalled:      return @"Loading_Status_Installed";
		case kBPListOutdated:       return @"Loading_Status_Outdated";
		case kBPListLeaves:         return @"Loading_Status_Leaves";
		case kBPListPinned:         return @"Loading_Status_Pinned";
		case kBPListRepositories:   return @"Loading_Status_Repositories";
		case kBPListInstalledCasks: return @"Loading_Status_InstalledCasks";
		case kBPListOutdatedCasks:  return @"Loading_Status_OutdatedCasks";
		case kBPListAll:            return @"Loading_Status_AllFormulae";
		case kBPListAllCasks:       return @"Loading_Status_AllCasks";

		case kBPListSearch:
			// Search is not part of a reload.
			return nil;
	}

	return nil;
}

+ (NSString *)statusForListMode:(BPListMode)mode
{
	NSString *key = [self localizationKeyForListMode:mode] ?: @"Loading_Status_Default";
	return NSLocalizedString(key, nil);
}

+ (BOOL)isSlowListMode:(BPListMode)mode
{
	// `brew formulae` and `brew casks` walk every tap. They share a 24h disk
	// cache, so this is the cold path — but cold is where the waiting happens.
	return mode == kBPListAll || mode == kBPListAllCasks;
}

@end
