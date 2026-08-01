//
//  BPHelperProtocol.h
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
 *  XPC surface of the helper. Deliberately ONE brew entry point: every
 *  operation in the app already funnels through
 *  -[BPHomebrewInterface performBrewCommandWithArguments:], so the sandbox
 *  boundary stays a single, auditable method rather than one per command.
 *
 *  Arguments are passed as an array and reach the shell as positional
 *  parameters (see -[BPHomebrewInterface formatArguments:sendOutputId:]),
 *  so they are never re-parsed by a shell.
 */
@protocol BPHelperProtocol <NSObject>

/// Runs `brew <arguments>` and replies with its exit status and combined output.
- (void)runBrewWithArguments:(NSArray<NSString *> *)arguments
					   reply:(void (^)(int status, NSString *output))reply;

/// Helper build version, so the app can detect app/helper skew after an update.
- (void)helperVersionWithReply:(void (^)(NSString *version))reply;

@end
