//
//  BPMockHomebrewInterface.h
//  Cakebrew
//
//  Test-support brew interface. When the app is launched with the -BPMockBrew
//  argument, +[BPHomebrewInterface sharedInterface] returns an instance of this
//  class, which serves deterministic fixture data instead of shelling out to a
//  real Homebrew install. This lets the UI tests drive journeys reliably.
//

#import "BPHomebrewInterface.h"

// Activated by the -BPMockBrew launch argument (checked in
// +[BPHomebrewInterface sharedInterface]).
@interface BPMockHomebrewInterface : BPHomebrewInterface
@end
