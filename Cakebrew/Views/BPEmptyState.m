//
//  BPEmptyState.m
//  Cakebrew
//

#import "BPEmptyState.h"
#import "BPSideBarController.h"

@implementation BPEmptyState

+ (instancetype)stateWithSymbol:(NSString *)symbol title:(NSString *)title message:(NSString *)message
{
	BPEmptyState *state = [[BPEmptyState alloc] init];
	state->_symbolName = [symbol copy];
	state->_titleKey = [title copy];
	state->_messageKey = [message copy];
	return state;
}

+ (instancetype)stateForSidebarRow:(NSInteger)row searching:(BOOL)searching
{
	if (searching)
	{
		return [self stateWithSymbol:@"magnifyingglass"
							   title:@"Empty_Search_Title"
							 message:@"Empty_Search_Message"];
	}

	switch ((FormulaeSideBarItem)row)
	{
		case FormulaeSideBarItemOutdated:
			// Good news, not an error, and it should read that way.
			return [self stateWithSymbol:@"checkmark.circle"
								   title:@"Empty_Outdated_Title"
								 message:@"Empty_Outdated_Message"];

		case FormulaeSideBarItemOutdatedCasks:
			return [self stateWithSymbol:@"checkmark.circle"
								   title:@"Empty_OutdatedCasks_Title"
								 message:@"Empty_OutdatedCasks_Message"];

		case FormulaeSideBarItemPinned:
			return [self stateWithSymbol:@"pin"
								   title:@"Empty_Pinned_Title"
								 message:@"Empty_Pinned_Message"];

		case FormulaeSideBarItemServices:
			return [self stateWithSymbol:@"gearshape.2"
								   title:@"Empty_Services_Title"
								 message:@"Empty_Services_Message"];

		case FormulaeSideBarItemInstalledCasks:
			return [self stateWithSymbol:@"macwindow"
								   title:@"Empty_Casks_Title"
								 message:@"Empty_Casks_Message"];

		case FormulaeSideBarItemLeaves:
			return [self stateWithSymbol:@"leaf"
								   title:@"Empty_Leaves_Title"
								 message:@"Empty_Leaves_Message"];

		default:
			// Still better than headers over blank space.
			return [self stateWithSymbol:@"tray"
								   title:@"Empty_Generic_Title"
								 message:@"Empty_Generic_Message"];
	}
}

+ (BOOL)shouldShowForRowCount:(NSInteger)rowCount loading:(BOOL)loading
{
	return rowCount == 0 && !loading;
}

@end
