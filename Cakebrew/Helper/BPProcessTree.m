//
//  BPProcessTree.m
//  Cakebrew
//

#import "BPProcessTree.h"
#import <signal.h>

@implementation BPProcessTree

+ (NSArray<NSNumber *> *)descendantsOfProcess:(pid_t)pid
{
	NSTask *pgrep = [[NSTask alloc] init];
	pgrep.launchPath = @"/usr/bin/pgrep";
	pgrep.arguments = @[@"-P", [@(pid) stringValue]];
	NSPipe *pipe = [NSPipe pipe];
	pgrep.standardOutput = pipe;
	pgrep.standardError = [NSPipe pipe];

	@try { [pgrep launch]; }
	@catch (NSException *exception) { return @[]; }

	NSData *data = [pipe.fileHandleForReading readDataToEndOfFile];
	[pgrep waitUntilExit];

	NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
	NSMutableArray<NSNumber *> *pids = [NSMutableArray array];
	for (NSString *line in [output componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
	{
		pid_t child = (pid_t)line.integerValue;
		if (child > 0)
		{
			// Depth first, so a grandchild is recorded before its parent dies.
			[pids addObjectsFromArray:[self descendantsOfProcess:child]];
			[pids addObject:@(child)];
		}
	}
	return pids;
}

+ (void)terminateProcesses:(NSArray<NSNumber *> *)pids
{
	for (NSNumber *pid in pids)
	{
		kill((pid_t)pid.intValue, SIGTERM);
	}
}

@end
