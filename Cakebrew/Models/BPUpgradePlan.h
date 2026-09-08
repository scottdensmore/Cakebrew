#import <Foundation/Foundation.h>
@class BPFormula;

NS_ASSUME_NONNULL_BEGIN

/// Immutable snapshot of a selected upgrade. Empty or invalid selections do
/// not execute; Upgrade All deliberately uses the interface's separate nil API.
@interface BPUpgradePlan : NSObject
- (instancetype)initWithSelection:(NSArray<BPFormula *> *)selection;

/// Blocking, formula batch then cask batch. Stops on the first failure or
/// cancellation, and returns YES only when every planned batch succeeded.
/// The runner must use the same token to prevent launch after cancellation.
- (BOOL)executeWithProgress:(NSProgress *)progress
                     runner:(BOOL (^)(NSArray<NSString *> *arguments))runner;
@end

NS_ASSUME_NONNULL_END
