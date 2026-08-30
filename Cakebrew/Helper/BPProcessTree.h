//
//  BPProcessTree.h
//  Cakebrew
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 *  Ending a brew run means ending its children too.
 *
 *  A run is a login shell executing brew, and brew spawns curl, git and
 *  compilers of its own. Terminating only the shell leaves a "cancelled"
 *  download still going, so both transports share this.
 */
@interface BPProcessTree : NSObject

/// Descendants of `pid`, deepest first. Collect *before* terminating the
/// parent: killing it reparents its children to launchd, where this walk can no
/// longer find them.
+ (NSArray<NSNumber *> *)descendantsOfProcess:(pid_t)pid;

/// Sends SIGTERM to every pid in `pids`.
+ (void)terminateProcesses:(NSArray<NSNumber *> *)pids;

@end

NS_ASSUME_NONNULL_END
