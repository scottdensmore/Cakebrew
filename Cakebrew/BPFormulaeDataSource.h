//
//  BPFormulaeDataSource.h
//  Cakebrew
//
//  Created by Marek Hrusovsky on 04/09/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "BPHomebrewInterface.h"
#import "BPFormula.h"

@interface BPFormulaeDataSource : NSObject <NSTableViewDataSource>

@property (nonatomic, assign) BPListMode mode;

- (instancetype)initWithMode:(BPListMode)aMode;
- (BPFormula *)formulaAtIndex:(NSInteger)index;
- (NSArray *)formulasAtIndexSet:(NSIndexSet *)indexSet;

/**
 *  Row of the formula with this name in the current list, or -1 if absent.
 *  Used to put the user's selection back after a reload.
 */
- (NSInteger)indexOfFormulaNamed:(NSString *)name;

/**
 *  `formulae` ordered by the table's sort descriptors.
 *
 *  Descriptor keys are the column identifiers. Name compares
 *  case-insensitively, versions compare naturally (so 9.0 precedes 10.0), and
 *  status compares by BPFormulaStatus rather than by the rendered string, which
 *  is localized and would otherwise order differently per language. The sort is
 *  stable, so equal keys keep their relative order instead of shuffling on
 *  every re-sort.
 */
+ (NSArray<BPFormula *> *)formulae:(NSArray<BPFormula *> *)formulae
						  sortedBy:(NSArray<NSSortDescriptor *> *)descriptors;
/// The table's current sort. Setting it re-sorts the backing array.
@property (nonatomic, copy) NSArray<NSSortDescriptor *> *sortDescriptors;

- (void)refreshBackingArray;

/**
 *  The value for a formula's Name cell. Plain name (NSString) normally; when
 *  pinned, an NSAttributedString of the name followed by the OS pin symbol.
 */
+ (id)nameCellValueForFormula:(BPFormula *)formula pinned:(BOOL)pinned;
@end
