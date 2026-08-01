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
	[connection resume];
	return YES;
}

#pragma mark - BPHelperProtocol

- (void)runBrewWithArguments:(NSArray<NSString *> *)arguments
					   reply:(void (^)(int status, NSString *output))reply
{
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

	// Same shape as the app's own command builder: a fixed command string with
	// the real arguments as positional parameters, so the shell never re-parses
	// user-supplied text. A login shell is used so brew finds its environment.
	NSMutableArray *shellArguments = [NSMutableArray arrayWithArray:@[@"-l", @"-c", @"brew \"$@\"", @"brew"]];
	[shellArguments addObjectsFromArray:arguments];

	NSTask *task = [[NSTask alloc] init];
	task.launchPath = shell;
	task.arguments = shellArguments;

	NSPipe *pipe = [NSPipe pipe];
	task.standardOutput = pipe;
	task.standardError = pipe;

	@try
	{
		[task launch];
	}
	@catch (NSException *exception)
	{
		reply(-1, exception.reason ?: @"failed to launch brew");
		return;
	}

	NSData *data = [[pipe fileHandleForReading] readDataToEndOfFile];
	[task waitUntilExit];

	NSString *output = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
	reply(task.terminationStatus, output);
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
