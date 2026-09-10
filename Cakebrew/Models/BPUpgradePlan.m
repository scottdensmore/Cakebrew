#import "BPUpgradePlan.h"
#import "BPFormula.h"

@interface BPUpgradeBatchResult ()
@property (nonatomic, copy) NSArray<NSString *> *arguments;
@property (nonatomic) BPUpgradeBatchStatus status;
@end
@implementation BPUpgradeBatchResult
@end
@interface BPUpgradeResult ()
@property (nonatomic, copy) NSArray<BPUpgradeBatchResult *> *batches;
@property (nonatomic) BOOL cancelled;
@end
@implementation BPUpgradeResult
- (BOOL)succeeded
{
    if (!self.batches.count || self.cancelled) return NO;
    for (BPUpgradeBatchResult *batch in self.batches) if (batch.status != BPUpgradeBatchSucceeded) return NO;
    return YES;
}
- (BOOL)attempted
{
    for (BPUpgradeBatchResult *batch in self.batches) if (batch.status != BPUpgradeBatchUnattempted) return YES;
    return NO;
}
@end
@interface BPUpgradePlan ()
@property (copy) NSArray<NSArray<NSString *> *> *batches;
@end

@implementation BPUpgradePlan
- (instancetype)initWithSelection:(NSArray<BPFormula *> *)selection
{
    if ((self = [super init])) {
        NSMutableArray *formulae = [NSMutableArray arrayWithObjects:@"upgrade", @"--formula", nil];
        NSMutableArray *casks = [NSMutableArray arrayWithObjects:@"upgrade", @"--cask", nil];
        for (BPFormula *formula in selection) {
            NSString *name = [formula.name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            // Never let a malformed named selection collapse into Upgrade All.
            if (!name.length) return self;
            [(formula.cask ? casks : formulae) addObject:name];
        }
        NSMutableArray *batches = [NSMutableArray array];
        if (formulae.count > 2) [batches addObject:[formulae copy]];
        if (casks.count > 2) [batches addObject:[casks copy]];
        _batches = [batches copy];
    }
    return self;
}

- (BOOL)executeWithProgress:(NSProgress *)progress runner:(BOOL (^)(NSArray<NSString *> *))runner
{
    return [self executeReportingWithProgress:progress runner:runner].succeeded;
}
- (BPUpgradeResult *)executeReportingWithProgress:(NSProgress *)progress runner:(BOOL (^)(NSArray<NSString *> *))runner
{
    NSMutableArray *results = [NSMutableArray array];
    BOOL stopped = progress.cancelled;
    for (NSArray<NSString *> *arguments in self.batches) {
        BPUpgradeBatchResult *batch = [[BPUpgradeBatchResult alloc] init];
        batch.arguments = arguments;
        batch.status = BPUpgradeBatchUnattempted;
        if (!stopped && !progress.cancelled) {
            BOOL succeeded = runner(arguments);
            batch.status = progress.cancelled ? BPUpgradeBatchCancelled : (succeeded ? BPUpgradeBatchSucceeded : BPUpgradeBatchFailed);
            stopped = batch.status != BPUpgradeBatchSucceeded;
        }
        [results addObject:batch];
    }
    BPUpgradeResult *result = [[BPUpgradeResult alloc] init];
    result.batches = results;
    result.cancelled = progress.cancelled;
    return result;
}
@end
