#import <Foundation/Foundation.h>
@class BPFormula;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, BPUpgradeBatchStatus) {
    BPUpgradeBatchUnattempted, BPUpgradeBatchSucceeded, BPUpgradeBatchFailed, BPUpgradeBatchCancelled
};
@interface BPUpgradeBatchResult : NSObject
@property (nonatomic, copy, readonly) NSArray<NSString *> *arguments;
@property (nonatomic, readonly) BPUpgradeBatchStatus status;
@end
@interface BPUpgradeResult : NSObject
@property (nonatomic, copy, readonly) NSArray<BPUpgradeBatchResult *> *batches;
@property (nonatomic, readonly) BOOL succeeded;
@property (nonatomic, readonly) BOOL cancelled;
@property (nonatomic, readonly) BOOL attempted;
@end

/// Immutable named selection. Empty or invalid selections never execute.
@interface BPUpgradePlan : NSObject
- (instancetype)initWithSelection:(NSArray<BPFormula *> *)selection;

/// Blocking, formula batch then cask batch. Stops on the first failure or
/// cancellation, and returns YES only when every planned batch succeeded.
/// The runner must use the same token to prevent launch after cancellation.
- (BPUpgradeResult *)executeReportingWithProgress:(NSProgress *)progress
    runner:(BOOL (^)(NSArray<NSString *> *arguments))runner;
- (BOOL)executeWithProgress:(NSProgress *)progress
                     runner:(BOOL (^)(NSArray<NSString *> *arguments))runner;
@end

NS_ASSUME_NONNULL_END
