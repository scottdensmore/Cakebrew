
//	BrewInterface.h
//	Cakebrew – The Homebrew GUI App for OS X
//
//  Created by Marek Hrusovsky on 24/08/15.
//	Copyright (c) 2014 Bruno Philipe. All rights reserved.
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

#import "BPTask.h"
#import "BPHelperOutputRelay.h"
#import "BPProcessTree.h"

static BOOL systemHasAppNap;

NSString *const kDidBeginBackgroundActivityNotification	= @"DidBeginBackgroundActivityNotification";
NSString *const kDidEndBackgroundActivityNotification	= @"DidEndBackgroundActivityNotification";

@interface BPTask()
{
	id activity;
	NSPipe *outputPipe;
	NSPipe *errorPipe;
	NSFileHandle *outputFileHandle;
	NSFileHandle *errorFileHandle;
	BPHelperOutputRelay *outputRelay;
	BPHelperOutputRelay *errorRelay;
	dispatch_queue_t deliveryQueue;
}

@property (strong) NSTask *task;
@property (readwrite) NSString *output;
@property (readwrite) NSString *error;
@property (readwrite) BOOL wasCancelled;

@end

@implementation BPTask

+ (void)load
{
	systemHasAppNap = [[NSProcessInfo processInfo] respondsToSelector:@selector(beginActivityWithOptions:reason:)];
}

- (instancetype)initWithPath:(NSString *)path arguments:(NSArray *)arguments
{
	self = [super init];
	if (self)
	{
		_task = [self taskWithPath:path arguments:arguments];
		_output = @"";
		_error = @"";

		// Chunks are handed to the update block here, one at a time and in
		// order. -execute drains this queue before returning, because
		// -performSyncBrewCommandWithArguments: reads the buffer its block
		// filled the instant -execute comes back.
		deliveryQueue = dispatch_queue_create("com.brunophilipe.Cakebrew.BPTask.Delivery", DISPATCH_QUEUE_SERIAL);
	}
	return self;
}

- (NSTask *)taskWithPath:(NSString *)path arguments:(NSArray *)arguments
{
	if (!path)
	{
		return nil;
	}

	NSTask *task = [[NSTask alloc] init];
	[task setLaunchPath:path];
	[task setArguments:arguments];
	return task;
}

#pragma mark - Reading

/// A relay that accumulates the whole stream and forwards each decoded chunk.
/// Shared with the helper transport, which needs exactly the same behaviour —
/// including holding back the tail of a multi-byte character split across two
/// reads, which brew produces constantly (✔ / ✘ / →).
- (BPHelperOutputRelay *)relayForwardingToUpdateBlock
{
	__weak BPTask *weakSelf = self;
	dispatch_queue_t queue = deliveryQueue;

	return [[BPHelperOutputRelay alloc] initWithSink:^(NSString *chunk) {
		// Enqueue rather than call through: the sink runs on the pipe's
		// readability queue, and blocking there stops the pipe draining.
		dispatch_async(queue, ^{
			BPTask *strongSelf = weakSelf;
			void (^update)(NSString *) = strongSelf.updateBlock;
			if (update && chunk.length > 0)
			{
				update(chunk);
			}
		});
	}];
}

- (void)configurePipes
{
	outputPipe = [NSPipe pipe];
	errorPipe = [NSPipe pipe];
	[self.task setStandardOutput:outputPipe];
	[self.task setStandardError:errorPipe];

	// Nothing ever writes to the child's stdin. Leaving the app's attached lets
	// a child that reads it wait forever instead of seeing EOF.
	[self.task setStandardInput:[NSFileHandle fileHandleWithNullDevice]];

	outputFileHandle = [outputPipe fileHandleForReading];
	errorFileHandle = [errorPipe fileHandleForReading];

	outputRelay = [self relayForwardingToUpdateBlock];
	errorRelay = [self relayForwardingToUpdateBlock];

	// Each pipe is drained on its own as data arrives. Reading one of them to
	// end-of-file (which is what this class used to do) leaves the other
	// filling up; once it hits the 64 KB buffer the child blocks on write and
	// can never exit.
	BPHelperOutputRelay *out = outputRelay;
	outputFileHandle.readabilityHandler = ^(NSFileHandle *handle) {
		[out appendData:[handle availableData]];
	};

	BPHelperOutputRelay *err = errorRelay;
	errorFileHandle.readabilityHandler = ^(NSFileHandle *handle) {
		[err appendData:[handle availableData]];
	};
}

/// Detaches the handlers and takes whatever landed between the last readability
/// callback and the process exiting.
- (void)finishReading
{
	outputFileHandle.readabilityHandler = nil;
	errorFileHandle.readabilityHandler = nil;

	[outputRelay appendData:[outputFileHandle readDataToEndOfFile]];
	[errorRelay appendData:[errorFileHandle readDataToEndOfFile]];

	self.output = outputRelay.accumulatedOutput;
	self.error = errorRelay.accumulatedOutput;
}

/// Blocks until every queued chunk has been handed to the update block.
- (void)deliverPendingChunks
{
	dispatch_sync(deliveryQueue, ^{});
}

#pragma mark - Running

- (int)execute
{
	[self configurePipes];
	[self beginActivity];
	@try {
		[self.task launch];
		[self.task waitUntilExit];

		[self finishReading];
		[self deliverPendingChunks];

		int status = [self.task terminationStatus];
		[self taskDidFinish];

		return status;
	}
	@catch (NSException *exception) {
		NSLog(@"Exception: %@", exception);
		[self cleanup];

		return -1;
	}
}

- (void)taskDidFinish
{
	[self endActivity];

	if ([self.delegate respondsToSelector:@selector(task:didFinishWithOutput:error:)])
	{
		[self.delegate task:self didFinishWithOutput:self.output error:self.error];
	}
}

- (void)beginActivity
{
	if (systemHasAppNap)
	{
		activity = [[NSProcessInfo processInfo] beginActivityWithOptions:NSActivityUserInitiated
																  reason:NSLocalizedString(@"Homebrew_AppNap_Task_Reason", nil)];

		[[NSNotificationCenter defaultCenter] postNotificationName:kDidBeginBackgroundActivityNotification object:self];
	}
}

- (void)endActivity
{
	if (systemHasAppNap && activity)
	{
		[[NSProcessInfo processInfo] endActivity:activity];
		activity = nil;

		[[NSNotificationCenter defaultCenter] postNotificationName:kDidEndBackgroundActivityNotification object:self];
	}
}

- (void)cancel
{
	self.wasCancelled = YES;

	NSTask *task = self.task;
	if (!task.isRunning)
	{
		return;
	}

	// Collect first: terminating the shell reparents its children to launchd,
	// after which pgrep -P can no longer find them.
	NSArray<NSNumber *> *descendants = [BPProcessTree descendantsOfProcess:task.processIdentifier];

	[task terminate];
	[BPProcessTree terminateProcesses:descendants];
}

- (void)cleanup
{
	outputFileHandle.readabilityHandler = nil;
	errorFileHandle.readabilityHandler = nil;

	if ([self.task isRunning])
	{
		[self.task terminate];
	}

	[self endActivity];
}

- (void)dealloc
{
	self.updateBlock = nil;
	[self cleanup];
}


@end
