//
//  BPService.h
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

typedef NS_ENUM(NSInteger, BPServiceStatus) {
	kBPServiceStatusNone,      // installed but not loaded
	kBPServiceStatusStarted,
	kBPServiceStatusStopped,
	kBPServiceStatusError,
	kBPServiceStatusScheduled,
	kBPServiceStatusUnknown,
};

/**
 *  A background service managed by `brew services` (postgres, redis, …).
 *  Services are not formulae-with-versions, so they get their own model.
 */
@interface BPService : NSObject

/// Localization key for a status. Never brew's raw JSON token, and never absent:
/// an unrecognised value maps to Unknown so a new brew status cannot reach the
/// UI as a bare string.
+ (NSString *)localizationKeyForStatus:(BPServiceStatus)status;

/// The status as shown to the user.
+ (NSString *)localizedNameForStatus:(BPServiceStatus)status;

@property (copy) NSString *name;
@property (copy) NSString *user;         // nil when the service isn't running
@property (strong) NSNumber *pid;        // nil when the service isn't running
@property (assign) BPServiceStatus status;
@property (copy) NSString *statusString; // raw status as reported by brew

/**
 *  Parses `brew services list --json` output. Defensive: returns an empty
 *  array for non-JSON output (brew errors), non-array JSON, and skips
 *  entries without a name. JSON nulls become nil properties.
 */
+ (NSArray<BPService *> *)servicesFromJSONString:(NSString *)output;

@end
