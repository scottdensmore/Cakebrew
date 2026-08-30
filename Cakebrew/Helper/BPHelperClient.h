//
//  BPHelperClient.h
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
 *  App side of the helper channel: runs brew in CakebrewHelper (outside the
 *  app sandbox) and relays its output back to the caller's block.
 */
@interface BPHelperClient : NSObject

+ (instancetype)sharedClient;

/**
 *  Runs brew via the helper, blocking until it exits.
 *
 *  @param block receives output chunks as they stream in; may be nil.
 *  @return YES when brew exited 0.
 */
/// Ends the command currently running over this client, if any.
- (void)cancelCurrentCommand;

- (BOOL)runBrewWithArguments:(NSArray<NSString *> *)arguments
				outputMarker:(NSString *)marker
				 outputBlock:(void (^)(NSString *output))block;

/**
 *  The tail of `output` that a sink has not already been given.
 *
 *  The reply and the streamed chunks travel independently, so the reply can
 *  win the race; this reconciles the two so no output is ever dropped.
 *  Returns nil when nothing is outstanding.
 */
+ (NSString *)undeliveredTailOfOutput:(NSString *)output deliveredLength:(NSUInteger)deliveredLength;

@end
