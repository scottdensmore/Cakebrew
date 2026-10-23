#import "BPFormulaeTableAction.h"

@implementation BPPackageOperationPresenter (OutPointerBridge)

+ (nullable NSAlert *)uninstallAlertForFormula:(nullable BPFormula *)formula
                               initialZapState:(BOOL)zapState
                                   zapCheckbox:(NSButton * _Nullable __autoreleasing * _Nullable)outCheckbox
{
    NSAlert *alert = [self uninstallAlertForFormula:formula initialZapState:zapState];
    if (outCheckbox) {
        *outCheckbox = [alert.accessoryView isKindOfClass:[NSButton class]] ? (NSButton *)alert.accessoryView : nil;
    }
    return alert;
}

+ (NSAlert *)tapInputAlertWithInputField:(NSTextField * _Nullable __autoreleasing * _Nullable)outField
{
    NSAlert *alert = [self tapInputAlert];
    if (outField) {
        *outField = [self tapInputHostForAlert:alert].inputField;
    }
    return alert;
}

@end
