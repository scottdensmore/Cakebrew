//
//  BPMockHomebrewInterface.m
//  Cakebrew
//

#import "BPMockHomebrewInterface.h"
#import "BPFormula.h"

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

		default:
			return @[];
	}
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

@end
