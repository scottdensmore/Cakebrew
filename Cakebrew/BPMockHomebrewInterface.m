//
//  BPMockHomebrewInterface.m
//  Cakebrew
//

#import "BPMockHomebrewInterface.h"
#import "BPFormula.h"
#import "BPService.h"
#import "BPServiceDetails.h"
#import "BPCleanupPreview.h"
#import "BPAutoremovePreview.h"

// Debug only. The mock must live inside the app binary — XCUITest drives the
// app out of process and cannot inject a class, so +sharedInterface finds it
// via NSClassFromString — but a shipping build has no business carrying a
// fixture interface, or honouring -BPMockBrew in a user's hands.
#if DEBUG

@interface BPMockHomebrewInterface ()
@property NSUInteger discoveryAttempts;
@property NSUInteger autoremovePreviews;
@end

@implementation BPMockHomebrewInterface

- (NSArray<BPFormula *> *)listModeForRemovalRefresh:(BPListMode)mode
{
	if (mode != kBPListInstalled && mode != kBPListLeaves && mode != kBPListOutdated) return nil;
	return [self listMode:mode];
}

- (NSArray<BPService *> *)listServicesForRemovalRefresh
{
	if ([NSProcessInfo.processInfo.arguments containsObject:@"-BPMockFailedAutoremoveRefresh"]) return nil;
	return [self listServices];
}

- (BPAutoremovePreview *)previewAutoremoveWithProgress:(NSProgress *)progress
{
	self.autoremovePreviews++;
	NSArray *arguments = NSProcessInfo.processInfo.arguments;
	NSString *output = @"==> Would autoremove 1 unneeded formula:\nmockunused\n";
	if ([arguments containsObject:@"-BPMockEmptyAutoremove"] || ([arguments containsObject:@"-BPMockChangedAutoremove"] && self.autoremovePreviews > 1)) output = @"";
	if ([arguments containsObject:@"-BPMockInvalidAutoremove"]) output = @"MOCK_UNRECOGNIZED\n";
	return [BPAutoremovePreview previewWithOutput:output succeeded:!progress.cancelled];
}
- (BOOL)removeUnusedFormulae:(NSArray<NSString *> *)names progress:(NSProgress *)progress output:(void (^)(NSString *))output
{
	if (progress.cancelled) return NO;
	if (output) output(@"MOCK_AUTOREMOVE_STARTED\n");
	NSArray *arguments = NSProcessInfo.processInfo.arguments;
	if ([arguments containsObject:@"-BPMockSlowAutoremove"]) {
		NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
		while (!progress.cancelled && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.05];
	}
	if (progress.cancelled) { if (output) output(@"MOCK_AUTOREMOVE_CANCELLED\n"); return NO; }
	if ([arguments containsObject:@"-BPMockFailedAutoremove"]) { if (output) output(@"MOCK_AUTOREMOVE_FAILED\n"); return NO; }
	if (output) output(@"MOCK_AUTOREMOVE_OK\n");
	return YES;
}

// Override the entire execution boundary: no shell validation, config command,
// or real brew call is allowed, including failure/retry journeys.
- (BPHomebrewDiscoveryResult)discoverHomebrew
{
	self.discoveryAttempts++;
	NSArray *arguments = NSProcessInfo.processInfo.arguments;
	if (self.discoveryAttempts > 1 && [arguments containsObject:@"-BPMockSlowHomebrewRetry"])
		[NSThread sleepForTimeInterval:3.0];
	if ([arguments containsObject:@"-BPMockHomebrewInvalidShell"]) return BPHomebrewDiscoveryInvalidShell;
	if ([arguments containsObject:@"-BPMockHomebrewCheckFailed"]) return BPHomebrewDiscoveryCheckFailed;
	if ([arguments containsObject:@"-BPMockHomebrewMissing"] ||
		([arguments containsObject:@"-BPMockHomebrewRecovers"] && self.discoveryAttempts == 1))
		return BPHomebrewDiscoveryMissing;
	return BPHomebrewDiscoveryAvailable;
}

// Serve deterministic fixture lists instead of running brew. installed / outdated
// / leaves / repositories are fetched fresh (not cached), so these drive the UI
// reproducibly.
- (NSArray<BPFormula *> *)listMode:(BPListMode)mode
{
	// -BPMockSlowCatalog holds the two catalog fetches long enough for a
	// journey to see the progress message they trigger. Real brew takes 80+
	// seconds here cold; the mock is instant, which makes the message
	// unobservable without this.
	if ((mode == kBPListAll || mode == kBPListAllCasks)
		&& [[[NSProcessInfo processInfo] arguments] containsObject:@"-BPMockSlowCatalog"]) {
		[NSThread sleepForTimeInterval:6.0];
	}

	switch (mode) {
		case kBPListInstalled:
			return @[ [BPFormula formulaWithName:@"mockwget" andVersion:@"1.0.0"],
					  [BPFormula formulaWithName:@"mockgit" andVersion:@"2.39.0"],
					  [BPFormula formulaWithName:@"mockcurl" andVersion:@"8.0.0"] ];

		case kBPListOutdated:
			// -BPMockEmptyOutdated gives journeys a genuinely empty list to
			// assert an empty state against; every fixture list is otherwise
			// populated, and a no-result *search* needs typing, which CI's
			// never-key window cannot do.
			if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-BPMockEmptyOutdated"]) {
				return @[];
			}
			return @[ [BPFormula formulaWithName:@"mockgit" version:@"2.39.0" andLatestVersion:@"2.40.0"] ];

		case kBPListLeaves:
			return @[ [BPFormula formulaWithName:@"mockwget" andVersion:@"1.0.0"] ];

		case kBPListAll:
			return @[ [BPFormula formulaWithName:@"mockwget"],
					  [BPFormula formulaWithName:@"mockgit"],
					  [BPFormula formulaWithName:@"mockcurl"],
					  [BPFormula formulaWithName:@"mockhtop"] ];

		case kBPListRepositories:
			return @[ [BPFormula formulaWithName:@"homebrew/core"],
					  [BPFormula formulaWithName:@"homebrew/cask"] ];

		case kBPListPinned:
			return @[ [BPFormula formulaWithName:@"mockgit"] ];

		case kBPListInstalledCasks:
			return [BPMockHomebrewInterface casksFromFormulae:
					@[ [BPFormula formulaWithName:@"mockchrome" andVersion:@"120.0"],
					   [BPFormula formulaWithName:@"mockvscode" andVersion:@"1.85.0"] ]];

		case kBPListOutdatedCasks:
			return [BPMockHomebrewInterface casksFromFormulae:
					@[ [BPFormula formulaWithName:@"mockchrome" version:@"120.0" andLatestVersion:@"121.0"] ]];

		case kBPListAllCasks:
			return [BPMockHomebrewInterface casksFromFormulae:
					@[ [BPFormula formulaWithName:@"mockchrome"],
					   [BPFormula formulaWithName:@"mockvscode"],
					   [BPFormula formulaWithName:@"mockfirefox"] ]];

		default:
			return @[];
	}
}

// The real cask list parsers mark their results; the mock bypasses them, so
// mark the fixtures here to keep operation dispatch (--cask) faithful.
+ (NSArray<BPFormula *> *)casksFromFormulae:(NSArray<BPFormula *> *)formulae
{
	for (BPFormula *formula in formulae) {
		formula.cask = YES;
	}
	return formulae;
}

// Stream a fixed, recognizable doctor report instead of running `brew doctor`.
// Deliberately several chunks: the Doctor view used to replace its whole
// document per chunk, so only the last one survived. The UI test asserts the
// first and last markers are both present, which pins that regression.
- (BOOL)runDoctorWithReturnBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_DOCTOR_OK\n");
		block(@"Checking for common problems...\n");
		block(@"MOCK_DOCTOR_DONE\nYour system is ready to brew.\n");
	}
	return YES;
}

// Stream a fixed, recognizable update report instead of running `brew update`.
- (BOOL)updateWithReturnBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_UPDATE_OK\nAlready up-to-date.\n");
	}
	return YES;
}

// Stream a fixed, recognizable cleanup report instead of running `brew cleanup`.
- (BOOL)runCleanupWithReturnBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_CLEANUP_OK\nFreed 0 bytes.\n");
	}
	return YES;
}

// A deterministic dry run, so the confirmation sheet has real numbers to show
// without walking the user's actual cache. -BPMockEmptyCleanup gives journeys
// the nothing-to-clean branch, which is otherwise unreachable under the mock.
- (BPCleanupPreview *)previewCleanup
{
	if ([[[NSProcessInfo processInfo] arguments] containsObject:@"-BPMockEmptyCleanup"]) {
		return [BPCleanupPreview previewFromOutput:@""];
	}

	return [BPCleanupPreview previewFromOutput:
			@"Would remove: /Users/mock/Library/Caches/Homebrew/mockwget--1.0.0.tar.gz (1.5MB)\n"
			@"Would remove: /opt/homebrew/Cellar/mockgit/2.38.0 (1,234 files, 45.6MB)\n"
			@"Would remove: /Users/mock/Library/Caches/Homebrew/mockcurl--7.9.0.tar.gz (2.1MB)\n"
			@"==> This operation would free approximately 49.2MB of disk space.\n"];
}

// Serve well-formed `brew info` output so selecting a formula doesn't shell out
// to real brew for a fixture name (which returns unparseable output and crashes
// BPFormula getInformation). The format matches what getInformation expects.
- (NSString *)informationForFormulaName:(NSString *)name
{
	return [NSString stringWithFormat:
			@"%@: stable 1.0.0\n"
			@"A mock formula used for Cakebrew UI tests.\n"
			@"https://example.com\n"
			@"Not installed\n", name];
}

- (NSString *)dependantsForFormulaName:(NSString *)name onlyInstalled:(BOOL)onlyInstalled
{
	return @"";
}

// Serve well-formed `brew info --cask` output (the real shape, with the ==>
// header and Installed marker) so selecting a cask exercises the cask parser.
- (NSString *)informationForCaskName:(NSString *)name
{
	return [NSString stringWithFormat:
			@"==> %@ (Mock App): 1.0.0 (auto_updates)\n"
			@"A mock cask used for Cakebrew UI tests.\n"
			@"https://example.com/cask\n"
			@"Installed (on request)\n"
			@"/usr/local/Caskroom/%@/1.0.0 (10MB)\n"
			@"From: https://example.com/%@.rb\n", name, name, name];
}

// Pin/unpin are no-ops under the mock so UI tests never shell out to real brew.
- (BOOL)pinFormula:(NSString *)formula withReturnBlock:(void (^)(NSString *))block
{
	return YES;
}

- (BOOL)uninstallCask:(NSString *)cask withReturnBlock:(void (^)(NSString *))block
{
	return [self uninstallCask:cask zap:NO withReturnBlock:block];
}

- (BOOL)uninstallCask:(NSString *)cask zap:(BOOL)zap withReturnBlock:(void (^)(NSString *))block
{
	return YES;
}

// Stream a fixed, recognizable upgrade report instead of running `brew upgrade`.
// Covers both a named selection and the no-operand "upgrade everything" path.
- (BOOL)upgradeFormulae:(NSArray *)formulae withReturnBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_UPGRADE_OK\nUpgraded 0 formulae.\n");
	}
	return YES;
}

- (BOOL)upgradeCasks:(NSArray *)casks withReturnBlock:(void (^)(NSString *))block
{
	return YES;
}

- (BOOL)installCask:(NSString *)cask withReturnBlock:(void (^)(NSString *))block
{
	return YES;
}

// Deterministic service fixtures: one running, one stopped.
- (NSArray<BPService *> *)listServices
{
	return [BPService servicesFromJSONString:
			@"[{\"name\":\"mockpostgres\",\"status\":\"started\",\"user\":\"mockuser\",\"pid\":123},"
			@"{\"name\":\"mockredis\",\"status\":\"none\",\"user\":null,\"pid\":null}]"];
}

- (BOOL)startService:(NSString *)name withReturnBlock:(void (^)(NSString *))block
{
	return YES;
}

- (BPServiceDetails *)serviceDetailsForName:(NSString *)name
{
	NSArray *arguments = NSProcessInfo.processInfo.arguments;
	if ([arguments containsObject:@"-BPMockServiceDetailsFailure"]) return [BPServiceDetails detailsForName:name
		output:@"Error: mock service details unavailable\nThe mock service list is still available." succeeded:NO];
	if ([arguments containsObject:@"-BPMockSlowServiceDetails"]) [NSThread sleepForTimeInterval:2];
	BOOL running = [name isEqualToString:@"mockpostgres"];
	NSDictionary *record = @{@"name": name, @"status": running ? @"started" : @"none",
		@"pid": running ? @123 : NSNull.null, @"user": running ? @"mockuser" : NSNull.null,
		@"file": @"/cakebrew-mock-missing/service.plist", @"log_path": @"/cakebrew-mock-missing/service.log",
		@"error_log_path": @"/cakebrew-mock-missing/service.log", @"exit_code": NSNull.null};
	NSData *data = [NSJSONSerialization dataWithJSONObject:@[record] options:0 error:nil];
	return [BPServiceDetails detailsForName:name output:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] succeeded:YES];
}

- (BOOL)stopService:(NSString *)name withReturnBlock:(void (^)(NSString *))block
{
	return YES;
}

- (BOOL)restartService:(NSString *)name withReturnBlock:(void (^)(NSString *))block
{
	return YES;
}

- (BOOL)unpinFormula:(NSString *)formula withReturnBlock:(void (^)(NSString *))block
{
	return YES;
}


// The formula-side mutating operations. Without these the mock inherits the
// real implementations and -BPMockBrew executes brew for real — which nothing
// caught only because every mutating journey pressed Cancel at the
// confirmation sheet.
- (BOOL)installFormula:(NSString *)formula withOptions:(NSArray *)options andReturnBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_INSTALL_OK\nInstalled 1 formula.\n");
	}
	return YES;
}

- (BOOL)uninstallFormula:(NSString *)formula withReturnBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_UNINSTALL_OK\nUninstalled 1 formula.\n");
	}
	return YES;
}

- (BOOL)tapRepository:(NSString *)repository withReturnsBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_TAP_OK\nTapped 1 repository.\n");
	}
	return YES;
}

- (BOOL)untapRepository:(NSString *)repository withReturnsBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_UNTAP_OK\nUntapped 1 repository.\n");
	}
	return YES;
}

// Both bundle operations touch the filesystem, so they are no-ops rather than
// writing a Brewfile wherever the panel happened to point.
- (NSError *)runBrewExportToolWithPath:(NSString *)path
{
	return nil;
}

- (BOOL)runBrewImportToolWithPath:(NSString *)path withReturnsBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_IMPORT_OK\nBrewfile applied.\n");
	}
	return YES;
}

- (BOOL)runBrewImportToolWithPath:(NSString *)path progress:(NSProgress *)progress withReturnsBlock:(void (^)(NSString *))block
{
 if (progress.cancelled) return NO;
 if (block) block(@"MOCK_IMPORT_STARTED\n");
 if ([[NSProcessInfo processInfo].arguments containsObject:@"-BPMockSlowBrewfileImport"]) {
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
  while (!progress.cancelled && deadline.timeIntervalSinceNow > 0) [NSThread sleepForTimeInterval:0.05];
 }
 if (progress.cancelled) { if (block) block(@"MOCK_IMPORT_CANCELLED\n"); return NO; }
 if ([[NSProcessInfo processInfo].arguments containsObject:@"-BPMockBrewfileImportFails"]) { if (block) block(@"MOCK_IMPORT_FAILED\n"); return NO; }
 if (block) block(@"MOCK_IMPORT_OK\n");
 return YES;
}

@end

#endif // DEBUG
