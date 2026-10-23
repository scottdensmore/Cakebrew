#import <Cocoa/Cocoa.h>
#import "BPFormulaInformation-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@protocol BPDockMenuActions <NSObject>
- (IBAction)updateHomebrew:(id)sender;
- (IBAction)upgradeAllOutdatedFormulae:(id)sender;
- (IBAction)showUnifiedUpdates:(id)sender;
@end

@protocol BPDockMenuTarget <BPDockMenuActions>
- (BOOL)isHomebrewInstalled;
@end

NS_ASSUME_NONNULL_END
