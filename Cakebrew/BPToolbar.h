#import <Cocoa/Cocoa.h>
#import "BPFormulaInformation-Swift.h"

@protocol BPToolbarProtocol <NSObject>

@required
- (void)performSearchWithString:(NSString *)search;
- (void)updateHomebrew:(id)sender;
- (void)upgradeSelectedFormulae:(id)sender;
- (void)showFormulaInfo:(id)sender;
- (void)tapRepository:(id)sender;
- (void)untapRepository:(id)sender;
- (void)cancelReload:(id)sender;
- (void)installFormula:(id)sender;
- (void)uninstallFormula:(id)sender;
@end
