#import "BPFormulaeTableView.h"
#import "BPHomebrewManager.h"
#import "BPSideBarController.h"
#import "BPToolbar.h"

NS_ASSUME_NONNULL_BEGIN

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
                               formulae:(nullable NSArray<BPFormula *> *)formulae
                               statuses:(nullable NSArray<NSNumber *> *)statuses;

+ (BPToolbarMode)toolbarModeForSidebarRow:(NSInteger)sidebarRow
                            selectedCount:(NSUInteger)selectedCount
                    selectedFormulaStatus:(BPFormulaStatus)status;

+ (BOOL)shouldShowFormulaInfoForSidebarRow:(NSInteger)sidebarRow;

+ (nullable NSString *)footerLocalizationKeyForSidebarRow:(NSInteger)sidebarRow
                                                searching:(BOOL)searching;

+ (BOOL)shouldRefreshVisibleListForPublishedMode:(BPListMode)publishedMode
                                      activeMode:(BPListMode)activeMode
                                       isLoading:(BOOL)isLoading;

+ (BOOL)shouldSyncInstalledHostMetadataForPublishedMode:(BPListMode)publishedMode
                                             activeMode:(BPListMode)activeMode
                                              isLoading:(BOOL)isLoading
                                   isUsingInstalledHost:(BOOL)isUsingInstalledHost;
@end

NS_ASSUME_NONNULL_END
