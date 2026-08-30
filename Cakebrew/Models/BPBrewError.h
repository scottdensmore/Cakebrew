//
//  BPBrewError.h
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

NS_ASSUME_NONNULL_BEGIN

extern NSString *const BPErrorDomain;

/// The exit status brew reported, as an NSNumber.
extern NSString *const BPBrewErrorExitStatusKey;

typedef NS_ENUM(NSInteger, BPBrewErrorCode) {
	/// The process could not be started at all.
	BPBrewErrorLaunchFailed = 1,
	/// brew ran and rejected the command.
	BPBrewErrorNonZeroExit = 2,
	/// brew succeeded but its output could not be understood.
	BPBrewErrorMalformedOutput = 3,
};

/**
 *  Turns a finished brew run into an error, or nil when it succeeded.
 *
 *  Replaces sniffing output for "Error:" prefixes against a domain literal with
 *  a magic code — the exit status is what actually says whether brew failed.
 */
@interface BPBrewError : NSObject

/// nil when `status` is 0. Keeps the tail of `output`, since a failure is
/// always at the end and an install can print thousands of lines.
+ (nullable NSError *)errorForExitStatus:(int)status output:(nullable NSString *)output;

@end

NS_ASSUME_NONNULL_END
