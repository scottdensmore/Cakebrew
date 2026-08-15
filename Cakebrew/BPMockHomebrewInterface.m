//
//  BPMockHomebrewInterface.m
//  Cakebrew
//

#import "BPMockHomebrewInterface.h"
#import "BPFormula.h"
#import "BPService.h"

@implementation BPMockHomebrewInterface

// Always report Homebrew as present so the app never shows the disabled overlay.
- (BOOL)checkForHomebrew
{
	return YES;
}

// Serve deterministic fixture lists instead of running brew. installed / outdated
// / leaves / repositories are fetched fresh (not cached), so these drive the UI
// reproducibly.
- (NSArray<BPFormula *> *)listMode:(BPListMode)mode
{
	switch (mode) {
		case kBPListInstalled:
			return @[ [BPFormula formulaWithName:@"mockwget" andVersion:@"1.0.0"],
					  [BPFormula formulaWithName:@"mockgit" andVersion:@"2.39.0"],
					  [BPFormula formulaWithName:@"mockcurl" andVersion:@"8.0.0"] ];

		case kBPListOutdated:
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
- (BOOL)runDoctorWithReturnBlock:(void (^)(NSString *))block
{
	if (block) {
		block(@"MOCK_DOCTOR_OK\nYour system is ready to brew.\n");
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

@end
