#import "BPUpgradePlan.h"
#import "BPFormula.h"

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
    if (!self.batches.count || progress.cancelled) return NO;
    for (NSArray<NSString *> *arguments in self.batches) {
        if (progress.cancelled || !runner(arguments)) return NO;
    }
    return !progress.cancelled;
}
@end
