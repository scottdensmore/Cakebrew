//
//  BPEmptyStateView.h
//  Cakebrew
//

#import <Cocoa/Cocoa.h>
#import "BPEmptyState.h"

NS_ASSUME_NONNULL_BEGIN

/// Symbol, title and one-line explanation, centred over an empty table.
@interface BPEmptyStateView : NSView

/// Shows `state` over `container`, or removes any existing view when nil.
+ (void)presentState:(nullable BPEmptyState *)state overView:(NSView *)container;

@end

NS_ASSUME_NONNULL_END
