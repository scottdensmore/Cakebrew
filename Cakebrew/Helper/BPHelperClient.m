//
//  BPHelperClient.m
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

#import "BPHelperClient.h"
#import "BPHelperProtocol.h"
#import "BPHelperSecurity.h"

/// Receives streamed chunks and forwards them to the caller's block.
@interface BPHelperSink : NSObject <BPHelperOutputSink>
@property (copy) void (^block)(NSString *output);
@property (assign) NSUInteger deliveredLength;
@end

@implementation BPHelperSink

- (void)helperDidProduceOutput:(NSString *)output
{
	if (output.length == 0)
	{
		return;
	}
	@synchronized (self)
	{
		self.deliveredLength += output.length;
	}
	// Kept cheap: this runs on the connection's delivery queue, and blocking
	// here stalls the rest of the stream (see BPHelperProtocol.h).
	if (self.block)
	{
		self.block(output);
	}
}

@end

@interface BPHelperClient ()
@property (strong) NSXPCConnection *currentConnection;
@end

@implementation BPHelperClient

+ (instancetype)sharedClient
{
	static BPHelperClient *client;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ client = [[BPHelperClient alloc] init]; });
	return client;
}

+ (NSString *)undeliveredTailOfOutput:(NSString *)output deliveredLength:(NSUInteger)deliveredLength
{
	if (output.length <= deliveredLength)
	{
		return nil;
	}
	return [output substringFromIndex:deliveredLength];
}

- (BOOL)runBrewWithArguments:(NSArray<NSString *> *)arguments
				outputMarker:(NSString *)marker
				 outputBlock:(void (^)(NSString *))block
{
	BPHelperSink *sink = [[BPHelperSink alloc] init];
	sink.block = block;

	// One connection per command keeps streamed chunks unambiguously owned by
	// the command that produced them.
	NSXPCConnection *connection =
		[[NSXPCConnection alloc] initWithMachServiceName:BPHelperMachServiceName options:0];
	connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(BPHelperProtocol)];
	connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(BPHelperOutputSink)];
	connection.exportedObject = sink;
	// Refuse to talk to anything that isn't our signed helper.
	[connection setCodeSigningRequirement:[BPHelperSecurity helperCodeSigningRequirement]];
	[connection resume];

	// One connection per command, so the connection identifies what to cancel.
	@synchronized (self) { self.currentConnection = connection; }

	__block int status = -1;
	__block NSString *fullOutput = nil;
	dispatch_semaphore_t finished = dispatch_semaphore_create(0);

	id<BPHelperProtocol> proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {
		NSLog(@"Cakebrew helper unavailable: %@", error.localizedDescription);
		dispatch_semaphore_signal(finished);
	}];

	[proxy runBrewWithArguments:(arguments ?: @[])
				   outputMarker:marker
						  reply:^(int replyStatus, NSString *output) {
		// Deliberately minimal: any real work here would stall delivery of the
		// sink messages queued behind it on the same connection.
		status = replyStatus;
		fullOutput = output;
		dispatch_semaphore_signal(finished);
	}];

	dispatch_semaphore_wait(finished, DISPATCH_TIME_FOREVER);

	// The reply can outrun the last chunks; hand over anything still missing so
	// callers that accumulate from the block never lose the tail.
	NSString *tail = [BPHelperClient undeliveredTailOfOutput:fullOutput deliveredLength:sink.deliveredLength];
	if (block && tail.length > 0)
	{
		block(tail);
	}

	[connection invalidate];
	return status == 0;
}

- (void)cancelCurrentCommand
{
	NSXPCConnection *connection;
	@synchronized (self) { connection = self.currentConnection; }
	if (!connection)
	{
		return;
	}

	// Fire and forget: the reply block exists so the helper can acknowledge,
	// but the caller is already tearing the operation down.
	id proxy = [connection remoteObjectProxyWithErrorHandler:^(NSError *error) {}];
	[proxy cancelBrewWithReply:^{}];
}

@end
