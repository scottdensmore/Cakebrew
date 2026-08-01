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
 *  Exported by the *app* so the helper can stream output back while a command
 *  runs. Without this the operation window could only show output after the
 *  command finished, regressing the live terminal view.
 */
@protocol BPHelperOutputSink <NSObject>

/// Called with each chunk of combined stdout/stderr as it is produced.
///
/// Implementations must return promptly and must not block: NSXPCConnection
/// delivers these and the runBrew reply on the same queue, so blocking here
/// (or in the reply block) stalls the rest of the stream. Measured: a client
/// that slept inside its reply block saw only 28 KB of a 106 KB command;
/// the same client with a non-blocking reply received all 106 KB in 26 chunks.
- (void)helperDidProduceOutput:(NSString *)output;

@end

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

/// Runs `brew <arguments>`, streaming output to the connection's
/// BPHelperOutputSink as it arrives, then replying with the exit status and
/// the complete output (so synchronous callers need no sink at all).
- (void)runBrewWithArguments:(NSArray<NSString *> *)arguments
					   reply:(void (^)(int status, NSString *output))reply;

/// Helper build version, so the app can detect app/helper skew after an update.
- (void)helperVersionWithReply:(void (^)(NSString *version))reply;

@end
