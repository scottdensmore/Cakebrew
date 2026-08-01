//
//  BPHelperOutputRelay.h
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
 *  Accumulates a task's output while forwarding it in chunks, mirroring what
 *  BPTask does locally today: callers that want the whole thing read
 *  -accumulatedOutput, while a live view gets each chunk as it arrives.
 *
 *  Safe to call from the pipe's readability handler (any queue). The sink is
 *  optional — synchronous callers pass nil.
 */
@interface BPHelperOutputRelay : NSObject

- (instancetype)initWithSink:(void (^)(NSString *chunk))sink NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Appends raw bytes read from the task; empty or nil data is ignored.
- (void)appendData:(NSData *)data;

/// Everything appended so far, decoded as UTF-8.
@property (readonly) NSString *accumulatedOutput;

@end
