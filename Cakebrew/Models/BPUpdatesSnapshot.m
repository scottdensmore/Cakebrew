#import "BPUpdatesSnapshot.h"
#import "BPFormula.h"

@implementation BPUpdateItem
+ (NSArray<BPUpdateItem *> *)itemsFromFormulae:(NSArray<BPFormula *> *)formulae cask:(BOOL)cask
{
    NSMutableArray *items = [NSMutableArray array];
    for (BPFormula *formula in formulae) {
        BPUpdateItem *item = [[self alloc] init];
        item->_name = [formula.name copy];
        item->_version = [formula.version copy] ?: @"";
        item->_latestVersion = [formula.latestVersion copy] ?: @"";
        item->_cask = cask;
        [items addObject:item];
    }
    return [items copy];
}
@end

@implementation BPUpdatesSnapshot
- (instancetype)initWithGeneration:(NSUInteger)generation formulae:(NSArray<BPFormula *> *)formulae
    casks:(NSArray<BPFormula *> *)casks pinnedFormulae:(NSArray<BPFormula *> *)formulaPins pinnedCasks:(NSArray<BPFormula *> *)caskPins
{
    return [self initWithGeneration:generation
        formulaItems:formulae ? [BPUpdateItem itemsFromFormulae:formulae cask:NO] : nil
        caskItems:casks ? [BPUpdateItem itemsFromFormulae:casks cask:YES] : nil
        pinnedFormulaNames:[formulaPins valueForKey:@"name"] pinnedCaskNames:[caskPins valueForKey:@"name"]];
}
- (instancetype)initWithGeneration:(NSUInteger)generation formulaItems:(NSArray<BPUpdateItem *> *)formulae
    caskItems:(NSArray<BPUpdateItem *> *)casks pinnedFormulaNames:(NSArray<NSString *> *)formulaPins pinnedCaskNames:(NSArray<NSString *> *)caskPins
{
    if (!formulae || !casks || !formulaPins || !caskPins) return nil;
    if ((self = [super init])) {
        _generation = generation;
        _formulae = [formulae copy]; _casks = [casks copy];
        _pinnedFormulaNames = [[NSArray alloc] initWithArray:formulaPins copyItems:YES];
        _pinnedCaskNames = [[NSArray alloc] initWithArray:caskPins copyItems:YES];
        NSMutableArray *eligibleFormulae = [NSMutableArray array], *eligibleCasks = [NSMutableArray array];
        NSMutableArray *excludedFormulae = [NSMutableArray array], *excludedCasks = [NSMutableArray array];
        for (NSNumber *cask in @[@NO, @YES]) {
            NSArray *pins = cask.boolValue ? _pinnedCaskNames : _pinnedFormulaNames;
            NSSet *tokens = [NSSet setWithArray:[pins valueForKey:@"lastPathComponent"]];
            NSMutableSet *seen = [NSMutableSet set];
            for (BPUpdateItem *item in (cask.boolValue ? _casks : _formulae)) {
                NSString *name = item.name;
                if (!name.length || ![name isEqualToString:[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]]) return nil;
                if ([seen containsObject:name]) continue;
                [seen addObject:name];
                BOOL pinned = [tokens containsObject:name.lastPathComponent];
                [(cask.boolValue ? (pinned ? excludedCasks : eligibleCasks) : (pinned ? excludedFormulae : eligibleFormulae)) addObject:name];
            }
        }
        _eligibleFormulae = [eligibleFormulae copy]; _eligibleCasks = [eligibleCasks copy];
        _excludedFormulae = [excludedFormulae copy]; _excludedCasks = [excludedCasks copy];
    }
    return self;
}
- (BOOL)hasEligibleUpdates { return self.eligibleFormulae.count + self.eligibleCasks.count > 0; }
- (NSArray<BPFormula *> *)eligibleSelection
{
    NSMutableArray *selection = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (BPUpdateItem *item in [self.formulae arrayByAddingObjectsFromArray:self.casks]) {
        NSString *identity = [NSString stringWithFormat:@"%d:%@", item.cask, item.name];
        if ([seen containsObject:identity]) continue;
        [seen addObject:identity];
        if (![(item.cask ? self.eligibleCasks : self.eligibleFormulae) containsObject:item.name]) continue;
        BPFormula *formula = [BPFormula formulaWithName:item.name version:item.version andLatestVersion:item.latestVersion];
        formula.cask = item.cask;
        [selection addObject:formula];
    }
    return [selection copy];
}
@end
