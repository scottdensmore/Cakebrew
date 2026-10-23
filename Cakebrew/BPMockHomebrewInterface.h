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

#ifdef BP_BRIDGING_HEADER_IMPORT
@class BPMockHomebrewInterface;
#else
#import "BPFormulaInformation-Swift.h"
#endif
