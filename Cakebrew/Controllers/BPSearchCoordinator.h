#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Main-thread search session state. Rendering and sidebar validation remain in
/// the view controller; the scheduler must coalesce pending work and run on main.
@interface BPSearchCoordinator : NSObject

@property (nonatomic, readonly, getter=isSearching) BOOL searching;
@property (nonatomic, readonly) NSInteger originalSidebarRow;
@property (nonatomic, readonly) NSUInteger generation;

- (instancetype)initWithPerformSearch:(void (^)(NSString *query))performSearch
						 cancelSearch:(dispatch_block_t)cancelSearch;
- (instancetype)initWithSchedule:(void (^)(NSTimeInterval delay, dispatch_block_t work))schedule
				   performSearch:(void (^)(NSString *query))performSearch
					cancelSearch:(dispatch_block_t)cancelSearch NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Schedule a nonempty field value; entering search mode waits for results.
- (void)scheduleQuery:(NSString *)query;
- (void)didReceiveResultsForSidebarRow:(NSInteger)row;
- (NSInteger)endSearchReturningSidebarRow;
- (void)cancelForNavigation;

@end

NS_ASSUME_NONNULL_END
