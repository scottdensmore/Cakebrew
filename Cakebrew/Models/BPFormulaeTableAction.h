#import "BPFormulaeTableView.h"
#import "BPHomebrewManager.h"
#import "BPSideBarController.h"
#import "BPToolbar.h"
#import "BPFormulaInformation-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface BPPackageOperationPresenter (OutPointerBridge)

+ (nullable NSAlert *)uninstallAlertForFormula:(nullable BPFormula *)formula
                               initialZapState:(BOOL)zapState
                                   zapCheckbox:(NSButton * _Nullable __autoreleasing * _Nullable)outCheckbox;

+ (NSAlert *)tapInputAlertWithInputField:(NSTextField * _Nullable __autoreleasing * _Nullable)outField;

@end

NS_ASSUME_NONNULL_END
