//
//	BrewInterface.m
//	Cakebrew – The Homebrew GUI App for OS X
//
//	Created by Vincent Saluzzo on 06/12/11.
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

#import "BPHomebrewInterface.h"
#import "BPCleanupPreview.h"
#import "BPTask.h"
#import "BPService.h"
#import "BPPreferences.h"
#import "BPHelperClient.h"
#import "BPBrewError.h"

#define kDEBUG_WARNING @"\
User Shell: %@\n\
Command: %@\n\
OS X Version: %@\n\n\
The outputs are going to be different if run from Xcode!!\n\
Installing and upgrading formulas is not advised in DEBUG mode!\n\n"

static NSString *cakebrewOutputIdentifier = @"+++++Cakebrew+++++";

@interface BPHomebrewInterfaceListCall : NSObject

@property (strong, readonly) NSArray *arguments;

- (instancetype)initWithArguments:(NSArray *)arguments;
- (NSArray *)parseData:(NSString *)data;
- (BPFormula *)parseFormulaItem:(NSString *)item;

@end

@interface BPHomebrewInterfaceListCallInstalled : BPHomebrewInterfaceListCall
@end

@interface BPHomebrewInterfaceListCallAll : BPHomebrewInterfaceListCall
@end

@interface BPHomebrewInterfaceListCallLeaves : BPHomebrewInterfaceListCall
@end

@interface BPHomebrewInterfaceListCallUpgradeable : BPHomebrewInterfaceListCall
@end

@interface BPHomebrewInterfaceListCallRepositories: BPHomebrewInterfaceListCall
@end

@interface BPHomebrewInterfaceListCallPinned : BPHomebrewInterfaceListCall
@end

@interface BPHomebrewInterfaceListCallInstalledCasks : BPHomebrewInterfaceListCallInstalled
@end

@interface BPHomebrewInterfaceListCallOutdatedCasks : BPHomebrewInterfaceListCallUpgradeable
@end

@interface BPHomebrewInterfaceListCallAllCasks : BPHomebrewInterfaceListCall
@end

@interface BPHomebrewInterface () <BPTaskCompleted>

@property (strong) NSString *path_shell;
@property (strong) NSMutableDictionary *tasks;
@property (strong) dispatch_queue_t taskOperationsQueue;
@property (strong) BPTask *currentOperationTask;

@end

@implementation BPHomebrewInterface

+ (instancetype)sharedInterface
{
	@synchronized(self)
	{
		static dispatch_once_t once;
		static BPHomebrewInterface *instance;
		dispatch_once(&once, ^ {
			// When launched with -BPMockBrew, use the fixture-backed mock interface
			// so UI tests run without a real Homebrew install. Resolved dynamically
			// so production code carries no dependency on the test-support class.
			Class interfaceClass = [BPHomebrewInterface class];
			if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-BPMockBrew"]) {
				Class mockClass = NSClassFromString(@"BPMockHomebrewInterface");
				if (mockClass) {
					interfaceClass = mockClass;
				}
			}
			instance = [[interfaceClass alloc] initUniqueInstance];
		});
		return instance;
	}
}

- (instancetype)initUniqueInstance
{
	self = [super init];
	if (self) {
		_tasks = [[NSMutableDictionary alloc] init];

		dispatch_queue_attr_t attributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_CONCURRENT,
																				  QOS_CLASS_USER_INITIATED,
																				  -5);

		_taskOperationsQueue = dispatch_queue_create("com.brunophilipe.Cakebrew.BPHomebrewInterface.Tasks", attributes);
		_brewTransport = [BPHomebrewInterface defaultTransportWhenSandboxed:[BPHomebrewInterface isRunningSandboxed]];
	}
	return self;
}

- (void)cleanup
{
	// Snapshot under the lock, then work outside it: -cleanup terminates
	// processes and must not hold the lock while doing so.
	NSArray<BPTask *> *tasks;
	@synchronized (self.tasks) { tasks = [self.tasks allValues]; }

	for (BPTask *task in tasks)
	{
		[task cleanup];
	}
}

- (void)cancelAllRunningTasks
{
	// Snapshot under the lock, then work outside it: -cancel terminates process
	// trees and must not hold the lock while doing so.
	NSArray<BPTask *> *tasks;
	@synchronized (self.tasks) { tasks = [self.tasks allValues]; }

	for (BPTask *task in tasks)
	{
		[task cancel];
	}

	[self.currentOperationTask cancel];
}

- (void)cancelCurrentOperation
{
	if (self.brewTransport == kBPBrewTransportHelper)
	{
		[[BPHelperClient sharedClient] cancelCurrentCommand];
		return;
	}

	[self.currentOperationTask cancel];
}

- (BOOL)hasCancellableOperation
{
	if (self.brewTransport == kBPBrewTransportHelper)
	{
		// The helper runs one command per connection; the app's own guard
		// ensures at most one is in flight.
		return YES;
	}
	return self.currentOperationTask != nil;
}

+ (NSURL *)installationURL
{
	return [NSURL URLWithString:@"https://brew.sh"];
}

+ (BPHomebrewDiscoveryResult)discoveryResultForOutput:(NSString *)output exitStatus:(int)status
{
	NSArray *start = [output componentsSeparatedByString:@"+++++Cakebrew Discovery+++++\n"];
	if (start.count != 2) return BPHomebrewDiscoveryCheckFailed;
	NSArray *end = [start.lastObject componentsSeparatedByString:@"+++++Cakebrew Discovery End+++++\n"];
	if (end.count != 2) return BPHomebrewDiscoveryCheckFailed;
	NSString *path = [end.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (status == 1 && path.length == 0) return BPHomebrewDiscoveryMissing;
	if (status != 0 || !path.isAbsolutePath || [path rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound)
		return BPHomebrewDiscoveryCheckFailed;
	BOOL directory = NO;
	NSFileManager *files = NSFileManager.defaultManager;
	return [files fileExistsAtPath:path isDirectory:&directory] && !directory && [files isExecutableFileAtPath:path]
		? BPHomebrewDiscoveryAvailable : BPHomebrewDiscoveryCheckFailed;
}

- (BPHomebrewDiscoveryResult)discoverHomebrew
{
	self.path_shell = [self getValidUserShellPath];
	if (!self.path_shell) return BPHomebrewDiscoveryInvalidShell;
	// Markers exclude login banners; preserve command-v's exit status instead
	// of treating diagnostics (notably "brew not found") as an executable.
	NSString *command = @"printf '\\n+++++Cakebrew Discovery+++++\\n'; command -v brew; cakebrew_status=$?; printf '+++++Cakebrew Discovery End+++++\\n'; exit \"$cakebrew_status\"";
	BPTask *task = [[BPTask alloc] initWithPath:self.path_shell arguments:@[@"-l", @"-c", command]];
	int status = [task execute];
	return [BPHomebrewInterface discoveryResultForOutput:task.output exitStatus:status];
}

#pragma mark - Private Methods

- (NSString *)getValidUserShellPath
{
	NSString *userShell = [[[NSProcessInfo processInfo] environment] objectForKey:@"SHELL"];
	
	// avoid executing stuff like /sbin/nologin as a shell
	BOOL isValidShell = NO;
	for (NSString *validShell in [[NSString stringWithContentsOfFile:@"/etc/shells" encoding:NSUTF8StringEncoding error:nil] componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]])
	{
		if ([[validShell stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] isEqualToString:userShell])
		{
			isValidShell = YES;
			break;
		}
	}
	
	if (!isValidShell || ![NSFileManager.defaultManager isExecutableFileAtPath:userShell]) return nil;
	
#ifdef DEBUG
	NSLog(@"shell: %@", userShell);
#endif
	
	return userShell;
}

- (NSArray *)formatArguments:(NSArray *)extraArguments sendOutputId:(BOOL)sendOutputID
{
	// Pass brew's arguments as the shell's positional parameters ("$@") instead
	// of interpolating them into the command string. The shell never re-parses
	// them, so shell metacharacters in user-supplied input (e.g. a tap name)
	// can't inject commands. A login shell (-l) is still used so brew finds its
	// PATH/environment. The output marker is a compile-time constant, so it is
	// safe to embed literally.
	NSString *command = sendOutputID
		? [NSString stringWithFormat:@"echo \"%@\";brew \"$@\"", cakebrewOutputIdentifier]
		: @"brew \"$@\"";

	// The operand after the command string is $0 (a conventional label); the
	// real arguments follow as $1, $2, … and expand via "$@".
	NSMutableArray *arguments = [NSMutableArray arrayWithArray:@[@"-l", @"-c", command, @"brew"]];
	[arguments addObjectsFromArray:(extraArguments ?: @[])];

	return arguments;
}

- (void)task:(BPTask *)task didFinishWithOutput:(NSString *)output error:(NSString *)error
{
	@synchronized (self.tasks) { [self.tasks removeObjectForKey:[NSString stringWithFormat:@"%p", task]]; }
}

- (BOOL)performBrewCommandWithArguments:(NSArray*)arguments dataReturnBlock:(void (^)(NSString*))block
{
	return [self performAsyncBrewCommandWithArguments:arguments wrapsSynchronousRequest:NO dataReturnBlock:block];
}

- (BOOL)performAsyncBrewCommandWithArguments:(NSArray*)arguments
					 wrapsSynchronousRequest:(BOOL)isSynchronous
							 dataReturnBlock:(void (^)(NSString*))block
{
	if (self.brewTransport == kBPBrewTransportHelper)
	{
		// The helper builds its own (identical) shell invocation, so it takes
		// brew's raw arguments plus the marker the sync path trims on.
		return [[BPHelperClient sharedClient] runBrewWithArguments:arguments
													 outputMarker:(isSynchronous ? cakebrewOutputIdentifier : nil)
													  outputBlock:block];
	}

	arguments = [self formatArguments:arguments sendOutputId:isSynchronous];

	if (!self.path_shell || !arguments)
	{
		return NO;
	}
	
	BPTask *task = [[BPTask alloc] initWithPath:self.path_shell arguments:arguments];
	task.delegate = self;
	task.updateBlock = block;

	// Only the operation the user is watching. List refreshes go through the
	// synchronous wrapper, so cancelling an install cannot abort a reload
	// running beside it.
	if (!isSynchronous)
	{
		self.currentOperationTask = task;
	}

	@synchronized (self.tasks) { [self.tasks setObject:task forKey:[NSString stringWithFormat:@"%p", task]]; }


#ifdef DEBUG
	if (!isSynchronous)
	{
		[self invokeOutputBlock:block withString:[NSString stringWithFormat:kDEBUG_WARNING,
												  self.path_shell,
												  [arguments componentsJoinedByString:@" "],
												  [[NSProcessInfo processInfo] operatingSystemVersionString]]];
	}
#endif
	
	int status = [task execute];

	if (self.currentOperationTask == task)
	{
		self.currentOperationTask = nil;
	}
	
	NSString *taskDoneString = [NSString stringWithFormat:@"%@: (%d) %@ %@!",
								NSLocalizedString(@"Homebrew_Task_Finished", nil),
								status,
								NSLocalizedString(@"Homebrew_Task_Finished_At", nil),
								[NSDateFormatter localizedStringFromDate:[NSDate date]
															   dateStyle:NSDateFormatterShortStyle
															   timeStyle:NSDateFormatterShortStyle]];
	
	[self invokeOutputBlock:block withString:taskDoneString];

	return status == 0;
}

// Invokes an optional output block. Callers may legitimately pass a nil block
// (e.g. pin/unpin, which don't stream output), so guard against calling a NULL
// block — doing so is an EXC_BAD_ACCESS crash.
- (void)invokeOutputBlock:(void (^)(NSString *))block withString:(NSString *)string
{
	if (block) {
		block(string);
	}
}

- (BOOL)isRunningBackgroundTask
{
	@synchronized (self.tasks) { return self.tasks.count > 0; }
}

/**
 * This method performs a brew command in an asynchronous mode so that long chunks of data can be returned,
 * but to the callee it behaves like a synchronous call.
 *
 * Note: Synchronous tasks were deprecated and removed completely in Nov 1st, 2016 due to numerous bugs. All
 * "synchronous" tasks should use this method instead.
 */
- (NSString*)performSyncBrewCommandWithArguments:(NSArray*)arguments
{
	NSString __block *finalOutput = nil;

	dispatch_queue_t queue = _taskOperationsQueue;

	dispatch_sync(queue, ^{
		NSMutableString *output = [NSMutableString new];

		// BPTask guarantees every chunk has reached this block before -execute
		// returns, so the buffer is complete by the time it is copied below.
		[self performAsyncBrewCommandWithArguments:arguments
						   wrapsSynchronousRequest:YES
								   dataReturnBlock:^(NSString *partialOutput)
		 {
			[output appendString:partialOutput];
		}];

		finalOutput = [output copy];
	});

	return [self removeLoginShellOutputFromString:finalOutput];
}

#pragma mark - Operations that return on finish

+ (BPBrewTransport)defaultTransportWhenSandboxed:(BOOL)sandboxed
{
	// A sandboxed process cannot exec brew at all ("operation not permitted"),
	// so it must go through the helper; everything else runs it directly.
	return sandboxed ? kBPBrewTransportHelper : kBPBrewTransportDirect;
}

+ (BOOL)isRunningSandboxed
{
	// Set by the sandbox for every containerised process.
	return [[NSProcessInfo processInfo] environment][@"APP_SANDBOX_CONTAINER_ID"] != nil;
}

+ (BOOL)isValidTapName:(NSString *)name
{
	NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	// Exactly owner/repo, each segment one or more of [A-Za-z0-9._-]. This
	// admits every real tap while excluding whitespace and shell metacharacters.
	static NSString *const pattern = @"^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$";
	NSRange range = NSMakeRange(0, trimmed.length);
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
	return [regex numberOfMatchesInString:trimmed options:0 range:range] == 1;
}

- (NSArray<BPFormula *> *)listMode:(BPListMode)mode
{
	BPHomebrewInterfaceListCall *listCall = nil;

	switch (mode) {
		case kBPListInstalled:
			listCall = [[BPHomebrewInterfaceListCallInstalled alloc] init];
			break;

		case kBPListAll:
			listCall = [[BPHomebrewInterfaceListCallAll alloc] init];
			break;

		case kBPListLeaves:
			listCall = [[BPHomebrewInterfaceListCallLeaves alloc] init];
			break;

		case kBPListOutdated:
			listCall = [[BPHomebrewInterfaceListCallUpgradeable alloc] init];
			break;

		case kBPListRepositories:
			listCall = [[BPHomebrewInterfaceListCallRepositories alloc] init];
			break;

		case kBPListPinned:
			listCall = [[BPHomebrewInterfaceListCallPinned alloc] init];
			break;

		case kBPListInstalledCasks:
			listCall = [[BPHomebrewInterfaceListCallInstalledCasks alloc] init];
			break;

		case kBPListOutdatedCasks:
			listCall = [[BPHomebrewInterfaceListCallOutdatedCasks alloc] init];
			break;

		case kBPListAllCasks:
			listCall = [[BPHomebrewInterfaceListCallAllCasks alloc] init];
			break;

		default:
			return nil;
	}

	NSString *string = [self performSyncBrewCommandWithArguments:listCall.arguments];

	if (string)
	{
		return [listCall parseData:string];
	}
	else
	{
		return nil;
	}
}

- (NSString *)informationForFormulaName:(NSString *)name;
{
	return [self performSyncBrewCommandWithArguments:@[@"info", name]];
}

- (NSString *)informationForCaskName:(NSString *)name
{
	return [self performSyncBrewCommandWithArguments:@[@"info", @"--cask", name]];
}

#pragma mark - Services

- (NSArray<BPService *> *)listServices
{
	NSString *output = [self performSyncBrewCommandWithArguments:@[@"services", @"list", @"--json"]];
	return output ? [BPService servicesFromJSONString:output] : @[];
}

// Service operations do not post the formulae-updated reload: they don't
// change formula/cask state, and the services UI refreshes its own list.
- (BOOL)startService:(NSString *)name withReturnBlock:(void (^)(NSString *))block
{
	return [self performBrewCommandWithArguments:@[@"services", @"start", name] dataReturnBlock:block];
}

- (BOOL)stopService:(NSString *)name withReturnBlock:(void (^)(NSString *))block
{
	return [self performBrewCommandWithArguments:@[@"services", @"stop", name] dataReturnBlock:block];
}

- (BOOL)restartService:(NSString *)name withReturnBlock:(void (^)(NSString *))block
{
	return [self performBrewCommandWithArguments:@[@"services", @"restart", name] dataReturnBlock:block];
}

- (NSString *)dependantsForFormulaName:(NSString *)name onlyInstalled:(BOOL)onlyInstalled
{
	NSMutableArray *arguments = [NSMutableArray arrayWithObject:@"uses"];

	if (onlyInstalled)
	{
		[arguments addObject:@"--installed"];
	}

	[arguments addObject:name];

	return [self performSyncBrewCommandWithArguments:arguments];
}

- (NSString*)removeLoginShellOutputFromString:(NSString*)string {
	if (string) {
		NSRange range = [string rangeOfString:cakebrewOutputIdentifier];
		if (range.location != NSNotFound) {
			return [string substringFromIndex:range.location + range.length+1];
		} else {
			return string;
		}
	}
	//If all else fails...
	return nil;
}

#pragma mark - Operations with live data callback block

- (BOOL)updateWithReturnBlock:(void (^)(NSString*output))block
{
	BOOL val = [self performBrewCommandWithArguments:@[@"update"] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"update"];
	return val;
}

+ (NSArray<NSString *> *)upgradeArgumentsWithPrefix:(NSArray<NSString *> *)prefix names:(NSArray<NSString *> *)names
{
	// Operands go to brew as the shell's positional parameters, so a blank one
	// is a real (empty) argv entry that brew rejects — it does not silently
	// disappear the way it did when arguments were joined into the command
	// string. Dropping blanks leaves a bare `brew upgrade`, which is exactly
	// how you ask Homebrew to upgrade everything outdated.
	NSMutableArray<NSString *> *arguments = [prefix mutableCopy];
	for (NSString *name in names) {
		NSString *trimmed = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		if (trimmed.length > 0) {
			[arguments addObject:trimmed];
		}
	}
	return arguments;
}

+ (NSArray<NSString *> *)argumentsForUpgradingFormulae:(NSArray<NSString *> *)formulae
{
	return [self upgradeArgumentsWithPrefix:@[@"upgrade"] names:formulae];
}

+ (NSArray<NSString *> *)argumentsForUpgradingCasks:(NSArray<NSString *> *)casks
{
	return [self upgradeArgumentsWithPrefix:@[@"upgrade", @"--cask"] names:casks];
}

- (BOOL)upgradeFormulae:(NSArray*)formulae withReturnBlock:(void (^)(NSString*output))block
{
	BOOL val = [self performBrewCommandWithArguments:[BPHomebrewInterface argumentsForUpgradingFormulae:formulae] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"upgrade"];
	return val;
}

- (BOOL)upgradeCasks:(NSArray*)casks withReturnBlock:(void (^)(NSString*output))block
{
	BOOL val = [self performBrewCommandWithArguments:[BPHomebrewInterface argumentsForUpgradingCasks:casks] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"upgrade"];
	return val;
}

- (BOOL)installFormula:(NSString*)formula withOptions:(NSArray*)options andReturnBlock:(void (^)(NSString*output))block
{
	NSArray *params = @[@"install", formula];
	if (options) {
		params = [params arrayByAddingObjectsFromArray:options];
	}
	BOOL val = [self performBrewCommandWithArguments:params dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"install"];
	return val;
}

- (BOOL)installCask:(NSString*)cask withReturnBlock:(void (^)(NSString*output))block
{
	BOOL val = [self performBrewCommandWithArguments:@[@"install", @"--cask", cask] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"install"];
	return val;
}

- (BOOL)uninstallFormula:(NSString*)formula withReturnBlock:(void (^)(NSString*output))block
{
	BOOL val = [self performBrewCommandWithArguments:@[@"uninstall", formula] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"uninstall"];
	return val;
}

+ (NSArray<NSString *> *)argumentsForUninstallingCask:(NSString *)cask zap:(BOOL)zap
{
	NSMutableArray<NSString *> *arguments = [@[@"uninstall", @"--cask"] mutableCopy];
	if (zap)
	{
		[arguments addObject:@"--zap"];
	}

	NSString *token = [cask stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (token.length > 0)
	{
		[arguments addObject:token];
	}
	return arguments;
}

- (BOOL)uninstallCask:(NSString*)cask withReturnBlock:(void (^)(NSString*output))block
{
	return [self uninstallCask:cask zap:NO withReturnBlock:block];
}

- (BOOL)uninstallCask:(NSString*)cask zap:(BOOL)zap withReturnBlock:(void (^)(NSString*output))block
{
	BOOL val = [self performBrewCommandWithArguments:[BPHomebrewInterface argumentsForUninstallingCask:cask zap:zap]
									 dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"uninstall"];
	return val;
}

- (BOOL)tapRepository:(NSString *)repository withReturnsBlock:(void (^)(NSString *))block
{
	BOOL val = [self performBrewCommandWithArguments:@[@"tap", repository] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"tap"];
	return val;
}

- (BOOL)untapRepository:(NSString *)repository withReturnsBlock:(void (^)(NSString *))block
{
	BOOL val = [self performBrewCommandWithArguments:@[@"untap", repository] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"untap"];
	return val;
}

- (BOOL)pinFormula:(NSString *)formula withReturnBlock:(void (^)(NSString *))block
{
	BOOL val = [self performBrewCommandWithArguments:@[@"pin", formula] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"pin"];
	return val;
}

- (BOOL)unpinFormula:(NSString *)formula withReturnBlock:(void (^)(NSString *))block
{
	BOOL val = [self performBrewCommandWithArguments:@[@"unpin", formula] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"unpin"];
	return val;
}

- (BOOL)runCleanupWithReturnBlock:(void (^)(NSString*output))block
{
	return [self performBrewCommandWithArguments:@[@"cleanup"] dataReturnBlock:block];
}

+ (NSArray<NSString *> *)argumentsForCleanupDryRun
{
	return @[@"cleanup", @"--dry-run"];
}

- (BPCleanupPreview *)previewCleanup
{
	NSString *output = [self performSyncBrewCommandWithArguments:[BPHomebrewInterface argumentsForCleanupDryRun]];
	return [BPCleanupPreview previewFromOutput:output];
}

- (BOOL)runDoctorWithReturnBlock:(void (^)(NSString*output))block
{
	BOOL val = [self performBrewCommandWithArguments:@[@"doctor"] dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"doctor"];
	return val;
}

- (NSError*)runBrewExportToolWithPath:(NSString*)path
{
	NSString *output = [self performSyncBrewCommandWithArguments:@[@"bundle",
																   @"dump",
																   @"--force",
																   [NSString stringWithFormat:@"--file=%@", path]]];
	
	[self sendDelegateFormulaeUpdatedCallForCommand:@"export"];
	
	if ([output length] == 0)
	{
		return nil;
	}
	else
	{
		__block NSError *error = nil;
		
		[output enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
			if ([line hasPrefix:@"Error:"] || [line hasPrefix:@"fatal:"])
			{
				// brew bundle dump reports failure in its output rather than
				// through an exit status this path can see, so the line is
				// still what identifies it — but the error itself is now built
				// the same way as every other one.
				error = [BPBrewError errorForExitStatus:1 output:line];
				
				*stop = YES;
			}
		}];
		
		return error;
	}
}

- (BOOL)runBrewImportToolWithPath:(NSString*)path withReturnsBlock:(void (^)(NSString *))block
{
	NSArray *arguments = @[@"bundle", [NSString stringWithFormat:@"--file=%@", path]];

	// The reload has to come *after* the import; posting it first made the
	// refresh observe pre-import state, so nothing the Brewfile installed
	// showed up until the next reload.
	BOOL result = [self performBrewCommandWithArguments:arguments
										dataReturnBlock:block];
	[self sendDelegateFormulaeUpdatedCallForCommand:@"bundle"];

	return result;
}

+ (BOOL)brewCommandChangesCatalogMembership:(NSString *)command
{
	if (command.length == 0)
	{
		return NO;
	}

	// Only commands that change which packages brew can see. Everything else —
	// install, uninstall, upgrade, pin, unpin, doctor, cleanup, export — moves
	// packages between the installed lists, which the cheap list calls already
	// pick up. Defaulting unknown commands to NO keeps a new operation from
	// silently reintroducing the 80-second catalog refetch.
	static NSSet<NSString *> *catalogChangingCommands = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		catalogChangingCommands = [NSSet setWithObjects:@"update", @"tap", @"untap", @"bundle", nil];
	});

	return [catalogChangingCommands containsObject:[command lowercaseString]];
}

- (void)sendDelegateFormulaeUpdatedCallForCommand:(NSString *)command
{
	BOOL rebuildCatalogs = [BPHomebrewInterface brewCommandChangesCatalogMembership:command];

	if (self.delegate) {
		id delegate = self.delegate;
		dispatch_async(dispatch_get_main_queue(), ^{
			[delegate homebrewInterfaceDidUpdateFormulaeRebuildingCatalogs:rebuildCatalogs];
		});
	}
}

@end

#pragma mark - Homebrew Interface List Calls

@implementation BPHomebrewInterfaceListCall

- (instancetype)initWithArguments:(NSArray *)arguments
{
	self = [super init];
	if (self) {
		_arguments = arguments;
	}
	return self;
}

- (NSArray<BPFormula *> *)parseData:(NSString *)data
{
	NSMutableArray<NSString *> *dataLines = [[data componentsSeparatedByString:@"\n"] mutableCopy];
	[dataLines removeLastObject];
	
	NSMutableArray<BPFormula *> *formulae = [NSMutableArray arrayWithCapacity:dataLines.count];
	
	for (NSString *item in dataLines) {
		BPFormula *formula = [self parseFormulaItem:item];
		if (formula) {
			[formulae addObject:formula];
		}
	}
	return formulae;
}

- (BPFormula *)parseFormulaItem:(NSString *)item
{
	return [BPFormula formulaWithName:item];
}

@end

@implementation BPHomebrewInterfaceListCallInstalled

- (instancetype)init
{
	return (BPHomebrewInterfaceListCallInstalled *)[super initWithArguments:@[@"list", @"--versions"]];
}

- (BPFormula *)parseFormulaItem:(NSString *)item
{
	NSArray *aux = [item componentsSeparatedByString:@" "];
	return [BPFormula formulaWithName:[aux firstObject] andVersion:[aux lastObject]];
}

@end

@implementation BPHomebrewInterfaceListCallAll

- (instancetype)init
{
	return (BPHomebrewInterfaceListCallAll *)[super initWithArguments:@[@"formulae"]];
}

@end

@implementation BPHomebrewInterfaceListCallLeaves

- (instancetype)init
{
	return (BPHomebrewInterfaceListCallLeaves *)[super initWithArguments:@[@"leaves"]];
}

@end

@implementation BPHomebrewInterfaceListCallUpgradeable

- (instancetype)init
{
	return (BPHomebrewInterfaceListCallUpgradeable *)[super initWithArguments:@[@"outdated", @"--verbose"]];
}

- (BPFormula *)parseFormulaItem:(NSString *)item
{
	// Formula lines compare with `<`; cask lines (OutdatedCasks subclass) with
	// `!=` because cask versions aren't ordered. Non-capturing so group
	// numbering is unchanged.
	static NSString *regexString = @"(\\S+)\\s\\(((.*, )*(.*))\\) (?:<|!=) (\\S+)";
	
	BPFormula __block *formula = nil;
	NSError *error = nil;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:regexString options:NSRegularExpressionCaseInsensitive error:&error];
	
	[regex enumerateMatchesInString:item options:0 range:NSMakeRange(0, [item length]) usingBlock:
	 ^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop)
	 {
		if (result.resultType == NSTextCheckingTypeRegularExpression && [result numberOfRanges] >= 4)
		{
			NSString *formulaName = [item substringWithRange:[result rangeAtIndex:1]];
			NSString *installedVersion = [item substringWithRange:[result rangeAtIndex:[result numberOfRanges] - 2]];
			NSString *latestVersion = [item substringWithRange:[result rangeAtIndex:[result numberOfRanges] - 1]];

			formula = [BPFormula formulaWithName:formulaName
										 version:installedVersion
								andLatestVersion:latestVersion];
		}
	}];
	
	if (!formula) {
		formula = [BPFormula formulaWithName:item];
	}
	
	return formula;
}

@end

@implementation BPHomebrewInterfaceListCallRepositories

- (instancetype)init
{
	return (BPHomebrewInterfaceListCallRepositories *)[super initWithArguments:@[@"tap"]];
}

@end

@implementation BPHomebrewInterfaceListCallPinned

- (instancetype)init
{
	return (BPHomebrewInterfaceListCallPinned *)[super initWithArguments:@[@"list", @"--pinned"]];
}

@end

@implementation BPHomebrewInterfaceListCallInstalledCasks

// Same "token version" output as installed formulae, so the parser is inherited
// from BPHomebrewInterfaceListCallInstalled; only the arguments differ.
- (instancetype)init
{
	return (BPHomebrewInterfaceListCallInstalledCasks *)[super initWithArguments:@[@"list", @"--cask", @"--versions"]];
}

- (BPFormula *)parseFormulaItem:(NSString *)item
{
	BPFormula *cask = [super parseFormulaItem:item];
	cask.cask = YES;
	return cask;
}

@end

@implementation BPHomebrewInterfaceListCallOutdatedCasks

// Same "(installed) != latest" line shape as the formula outdated list (the
// shared regex accepts both comparators); only the arguments and flag differ.
// The greedy preference includes auto-updating casks in the listing.
- (instancetype)init
{
	NSArray *arguments = @[@"outdated", @"--cask", @"--verbose"];
	if ([BPPreferences greedyCaskUpgrades]) {
		arguments = [arguments arrayByAddingObject:@"--greedy"];
	}
	return (BPHomebrewInterfaceListCallOutdatedCasks *)[super initWithArguments:arguments];
}

- (BPFormula *)parseFormulaItem:(NSString *)item
{
	BPFormula *cask = [super parseFormulaItem:item];
	cask.cask = YES;
	return cask;
}

@end

@implementation BPHomebrewInterfaceListCallAllCasks

// `brew casks` prints one token per line (like `brew formulae`); the base
// name-only parser applies.
- (instancetype)init
{
	return (BPHomebrewInterfaceListCallAllCasks *)[super initWithArguments:@[@"casks"]];
}

- (BPFormula *)parseFormulaItem:(NSString *)item
{
	BPFormula *cask = [super parseFormulaItem:item];
	cask.cask = YES;
	return cask;
}

@end
