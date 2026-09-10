#import <Foundation/Foundation.h>
@class BPFormula;

NS_ASSUME_NONNULL_BEGIN
/// Immutable scalar values; never retains the mutable manager models.
@interface BPUpdateItem : NSObject
@property (nonatomic, copy, readonly) NSString *name;
@property (nonatomic, copy, readonly) NSString *version;
@property (nonatomic, copy, readonly) NSString *latestVersion;
@property (nonatomic, readonly) BOOL cask;
+ (NSArray<BPUpdateItem *> *)itemsFromFormulae:(NSArray<BPFormula *> *)formulae cask:(BOOL)cask;
@end

/// Actionable only after all four successful inputs of one reload. Empty lists
/// are successful; nil means unavailable. Pin keys are namespace-local tokens.
@interface BPUpdatesSnapshot : NSObject
@property (nonatomic, readonly) NSUInteger generation;
@property (nonatomic, copy, readonly) NSArray<BPUpdateItem *> *formulae;
@property (nonatomic, copy, readonly) NSArray<BPUpdateItem *> *casks;
@property (nonatomic, copy, readonly) NSArray<NSString *> *pinnedFormulaNames;
@property (nonatomic, copy, readonly) NSArray<NSString *> *pinnedCaskNames;
@property (nonatomic, copy, readonly) NSArray<NSString *> *eligibleFormulae;
@property (nonatomic, copy, readonly) NSArray<NSString *> *eligibleCasks;
@property (nonatomic, copy, readonly) NSArray<NSString *> *excludedFormulae;
@property (nonatomic, copy, readonly) NSArray<NSString *> *excludedCasks;
@property (nonatomic, readonly) BOOL hasEligibleUpdates;
- (nullable instancetype)initWithGeneration:(NSUInteger)generation
    formulae:(nullable NSArray<BPFormula *> *)formulae casks:(nullable NSArray<BPFormula *> *)casks
    pinnedFormulae:(nullable NSArray<BPFormula *> *)pinnedFormulae pinnedCasks:(nullable NSArray<BPFormula *> *)pinnedCasks;
- (nullable instancetype)initWithGeneration:(NSUInteger)generation
    formulaItems:(nullable NSArray<BPUpdateItem *> *)formulae caskItems:(nullable NSArray<BPUpdateItem *> *)casks
    pinnedFormulaNames:(nullable NSArray<NSString *> *)formulaPins pinnedCaskNames:(nullable NSArray<NSString *> *)caskPins;
/// Fresh detached models for the existing operation controller boundary.
- (NSArray<BPFormula *> *)eligibleSelection;
@end
NS_ASSUME_NONNULL_END
