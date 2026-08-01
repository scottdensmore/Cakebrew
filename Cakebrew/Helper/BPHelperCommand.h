//
//  BPHelperCommand.h
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
 *  Builds the login-shell invocation used to run brew.
 *
 *  Everything variable travels as a positional parameter, so the shell never
 *  re-parses caller-supplied text (see the injection fix in #58).
 */
@interface BPHelperCommand : NSObject

/**
 *  @param arguments brew's own arguments (e.g. @[@"list", @"--versions"]).
 *  @param marker    optional line echoed before brew runs, so callers can
 *                   discard login-shell profile noise that precedes it.
 *                   Pass nil or @"" for none.
 */
+ (NSArray<NSString *> *)shellArgumentsForBrewArguments:(NSArray<NSString *> *)arguments
										   outputMarker:(NSString *)marker;

@end
