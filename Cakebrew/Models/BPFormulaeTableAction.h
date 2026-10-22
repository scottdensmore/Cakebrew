#import "BPFormulaeTableView.h"
#import "BPHomebrewManager.h"
#import "BPSideBarController.h"
#import "BPToolbar.h"

@class BPCleanupPreview;
@class BPUpdatesSnapshot;

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

+ (BOOL)shouldSyncUnifiedUpdatesForPublishedMode:(BPListMode)publishedMode
                                       isLoading:(BOOL)isLoading
                       isUsingUnifiedUpdatesHost:(BOOL)isUsingUnifiedUpdatesHost;
@end

/// Directly unit-testable presenter for confirmation sheets, operation summaries,
/// and heterogeneous selection resolution extracted from BPHomebrewViewController.
@interface BPPackageOperationPresenter : NSObject

+ (nullable NSAlert *)installAlertForFormula:(nullable BPFormula *)formula;

+ (nullable NSAlert *)uninstallAlertForFormula:(nullable BPFormula *)formula
                               initialZapState:(BOOL)zapState
                                   zapCheckbox:(NSButton * _Nullable * _Nullable)outCheckbox;

+ (nullable NSAlert *)upgradeAlertForFormulae:(nullable NSArray<BPFormula *> *)formulae;

+ (nullable NSString *)updatesReviewSummaryForSnapshot:(nullable BPUpdatesSnapshot *)snapshot;

+ (nullable NSAlert *)upgradeAllAlertForSnapshot:(nullable BPUpdatesSnapshot *)snapshot;

+ (NSAlert *)updatesChangedAlert;

+ (NSAlert *)tapInputAlertWithInputField:(NSTextField * _Nullable * _Nullable)outField;

+ (NSAlert *)invalidTapAlert;

+ (nullable NSAlert *)untapAlertForFormula:(nullable BPFormula *)formula;

+ (NSString *)cleanupConfirmationBodyForPreview:(BPCleanupPreview *)preview;

+ (NSAlert *)cleanupAlertForPreview:(BPCleanupPreview *)preview;

+ (NSDictionary<NSString *, NSArray<NSString *> *> *)brewfileInventoriesForInstalledFormulae:(nullable NSArray<BPFormula *> *)formulae
                                                                              installedCasks:(nullable NSArray<BPFormula *> *)casks
                                                                                repositories:(nullable NSArray<BPFormula *> *)repositories;

+ (NSArray<BPFormula *> *)resolvedSelectionForFormulaNames:(NSArray<NSString *> *)formulaNames
                                                 caskNames:(NSArray<NSString *> *)caskNames
                                          outdatedFormulae:(nullable NSArray<BPFormula *> *)outdatedFormulae
                                             outdatedCasks:(nullable NSArray<BPFormula *> *)outdatedCasks;

@end

NS_ASSUME_NONNULL_END
