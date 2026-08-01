//
//  main.m
//  CakebrewHelper
//
//  A per-user launchd agent that runs `brew` on behalf of the sandboxed app.
//  Spawned by launchd (not forked by the app), so it does not inherit the
//  app's sandbox: it sees the real home directory, so brew's download cache
//  and `brew services` LaunchAgents land where the user's own brew expects
//  them. It runs as the user (never root — Homebrew refuses to run as root).
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
#import "BPHelperProtocol.h"
#import "BPHelperSecurity.h"
#import "BPHelperOutputRelay.h"
#import "BPHelperCommand.h"

@interface BPHelperService : NSObject <NSXPCListenerDelegate, BPHelperProtocol>
@end

@implementation BPHelperService

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)connection
{
	// The listener already enforces the client's designated requirement (set in
	// main), so anything arriving here is a genuine, correctly signed Cakebrew.
	connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(BPHelperProtocol)];
	connection.exportedObject = self;
	// The app exports a sink so output can be streamed back mid-command.
	connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(BPHelperOutputSink)];
	[connection resume];
	return YES;
}

#pragma mark - BPHelperProtocol

- (void)runBrewWithArguments:(NSArray<NSString *> *)arguments
				outputMarker:(NSString *)marker
					   reply:(void (^)(int status, NSString *output))reply
{
	if (marker != nil && ![marker isKindOfClass:[NSString class]])
	{
		reply(-1, @"invalid arguments");
		return;
	}
	if (![arguments isKindOfClass:[NSArray class]])
	{
		reply(-1, @"invalid arguments");
		return;
	}
	for (id argument in arguments)
	{
		if (![argument isKindOfClass:[NSString class]])
		{
			reply(-1, @"invalid arguments");
			return;
		}
	}

	NSString *shell = [[[NSProcessInfo processInfo] environment] objectForKey:@"SHELL"] ?: @"/bin/zsh";

	NSTask *task = [[NSTask alloc] init];
	task.launchPath = shell;
	task.arguments = [BPHelperCommand shellArgumentsForBrewArguments:arguments outputMarker:marker];

	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = pipe;

	// Stream chunks to the app as they arrive so the operation window stays
	// live, and accumulate the whole output for the reply. The sink is the
	// connection's exported object; synchronous callers simply export none.
	id<BPHelperOutputSink> sink = [[NSXPCConnection currentConnection] remoteObjectProxy];
	BPHelperOutputRelay *relay = [[BPHelperOutputRelay alloc] initWithSink:^(NSString *chunk) {
		[sink helperDidProduceOutput:chunk];
	}];

	NSFileHandle *readHandle = [pipe fileHandleForReading];
	readHandle.readabilityHandler = ^(NSFileHandle *handle) {
		[relay appendData:[handle availableData]];
	};

	@try
	{
		[task launch];
	}
	@catch (NSException *exception)
	{
		readHandle.readabilityHandler = nil;
		reply(-1, exception.reason ?: @"failed to launch brew");
		return;
	}

	[task waitUntilExit];

	// Detach the handler, then drain whatever landed between the last
	// readability callback and the process exiting.
	readHandle.readabilityHandler = nil;
	[relay appendData:[readHandle readDataToEndOfFile]];

	reply(task.terminationStatus, relay.accumulatedOutput);
}

- (void)helperVersionWithReply:(void (^)(NSString *version))reply
{
	NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
	reply(version ?: @"unknown");
}

@end

int main(int argc, const char *argv[])
{
	@autoreleasepool
	{
		BPHelperService *service = [[BPHelperService alloc] init];

		NSXPCListener *listener = [[NSXPCListener alloc] initWithMachServiceName:BPHelperMachServiceName];
		listener.delegate = service;

		// The security boundary. Without this the helper is a sandbox-escape
		// service any local process can drive: an unsigned test binary was able
		// to run brew through an unpinned listener.
		[listener setConnectionCodeSigningRequirement:[BPHelperSecurity clientCodeSigningRequirement]];

		[listener resume];
		[[NSRunLoop currentRunLoop] run];
	}
	return 0;
}
