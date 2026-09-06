#import "BPFormulaeTableView.h"
#import "BPHomebrewManager.h"

typedef NS_ENUM(NSInteger, BPFormulaeTableAction) {
    BPFormulaeTableActionNone,
    BPFormulaeTableActionInstall,
    BPFormulaeTableActionUpgrade,
    BPFormulaeTableActionInfo,
    BPFormulaeTableActionUninstall
};

/// Pure, fail-closed policy; the controller supplies current namespace-aware statuses.
@interface BPFormulaeTableActions : NSObject
+ (BPFormulaeTableAction)actionForRequest:(BPFormulaeTableRequest)request
                                   mode:(BPListMode)mode
                               formulae:(NSArray<BPFormula *> *)formulae
                               statuses:(NSArray<NSNumber *> *)statuses;
@end
