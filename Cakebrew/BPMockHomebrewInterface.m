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

@end
