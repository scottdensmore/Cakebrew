#import "BPSearchCoordinator.h"
#import "BPTimedDispatch.h"

@interface BPSearchCoordinator ()
@property (nonatomic, copy) void (^schedule)(NSTimeInterval, dispatch_block_t);
@property (nonatomic, copy) void (^performSearch)(NSString *);
@property (nonatomic, copy) dispatch_block_t cancelSearch;
@property (nonatomic, readwrite, getter=isSearching) BOOL searching;
@property (nonatomic, readwrite) NSInteger originalSidebarRow;
@property (nonatomic, readwrite) NSUInteger generation;
@end

@implementation BPSearchCoordinator

- (instancetype)initWithPerformSearch:(void (^)(NSString *))performSearch
						 cancelSearch:(dispatch_block_t)cancelSearch
{
	BPTimedDispatch *timedDispatch = [BPTimedDispatch new];
	return [self initWithSchedule:^(NSTimeInterval delay, dispatch_block_t work) {
		[timedDispatch scheduleDispatchAfterTimeInterval:delay
			inQueue:dispatch_get_main_queue() ofBlock:work];
	} performSearch:performSearch cancelSearch:cancelSearch];
}

- (instancetype)initWithSchedule:(void (^)(NSTimeInterval, dispatch_block_t))schedule
				   performSearch:(void (^)(NSString *))performSearch
					cancelSearch:(dispatch_block_t)cancelSearch
{
	self = [super init];
	if (self) {
		_schedule = [schedule copy];
		_performSearch = [performSearch copy];
		_cancelSearch = [cancelSearch copy];
	}
	return self;
}

- (void)scheduleQuery:(NSString *)query
{
	NSAssert(NSThread.isMainThread, @"Search coordination must run on the main thread");
	NSParameterAssert(query.length > 0);
	NSUInteger generation = self.generation;
	__weak typeof(self) weakSelf = self;
	self.schedule(0.15, ^{
		__strong typeof(weakSelf) self = weakSelf;
		if (!self || generation != self.generation) return;
		self.performSearch(query);
	});
}

- (void)didReceiveResultsForSidebarRow:(NSInteger)row
{
	NSAssert(NSThread.isMainThread, @"Search coordination must run on the main thread");
	if (!self.isSearching) self.originalSidebarRow = row;
	self.searching = YES;
}

- (NSInteger)endSearchReturningSidebarRow
{
	NSAssert(NSThread.isMainThread, @"Search coordination must run on the main thread");
	self.generation += 1;
	self.searching = NO;
	self.cancelSearch();
	return self.originalSidebarRow;
}

- (void)cancelForNavigation
{
	NSAssert(NSThread.isMainThread, @"Search coordination must run on the main thread");
	self.generation += 1;
	self.searching = NO;
	self.cancelSearch();
}

@end
