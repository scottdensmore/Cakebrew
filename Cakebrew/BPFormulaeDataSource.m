//
//  BPFormulaeDataSource.m
//  Cakebrew
//
//  Created by Marek Hrusovsky on 04/09/14.
//  Copyright (c) 2014 Bruno Philipe. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "BPFormulaeDataSource.h"
#import "BPHomebrewManager.h"
#import "BPFormulaeTableView.h"
#import "BPPreferences.h"

@interface BPFormulaeDataSource()
@property (nonatomic, strong) NSArray *formulaeArray;
@end

@implementation BPFormulaeDataSource

- (instancetype)init
{
	return [self initWithMode:kBPListAll];
}

+ (id)nameCellValueForFormula:(BPFormula *)formula pinned:(BOOL)pinned
{
	NSString *name = [formula name];
	if (!pinned || name.length == 0)
	{
		return name ?: @"";
	}

	// Name followed by the OS pin symbol so pinned formulae are spottable in
	// the list without selecting them.
	NSMutableAttributedString *value = [[NSMutableAttributedString alloc] initWithString:[name stringByAppendingString:@" "]];

	NSImage *pin = [NSImage imageWithSystemSymbolName:@"pin.fill" accessibilityDescription:@"Pinned"];
	if (pin)
	{
		NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:[NSFont smallSystemFontSize]
																							weight:NSFontWeightRegular];
		NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
		attachment.image = [pin imageWithSymbolConfiguration:config] ?: pin;
		[value appendAttributedString:[NSAttributedString attributedStringWithAttachment:attachment]];
	}

	return value;
}

- (instancetype)initWithMode:(BPListMode)aMode
{
	self = [super init];
	if (self) {
		_mode = aMode;
	}
	[self refreshBackingArray];
	return self;
}

- (void)setMode:(BPListMode)mode
{
	_mode = mode;
	[self refreshBackingArray];
}

- (void)setSortDescriptors:(NSArray<NSSortDescriptor *> *)sortDescriptors
{
	_sortDescriptors = [sortDescriptors copy];
	[self refreshBackingArray];
}

- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray<NSSortDescriptor *> *)oldDescriptors
{
	self.sortDescriptors = tableView.sortDescriptors;

	// Remembered so the chosen sort survives relaunch.
	NSSortDescriptor *descriptor = tableView.sortDescriptors.firstObject;
	[BPPreferences setSortColumnIdentifier:descriptor.key];
	[BPPreferences setSortAscending:descriptor ? descriptor.ascending : YES];

	[tableView reloadData];
}

- (void)refreshBackingArray
{
	switch (self.mode) {
		case kBPListAll:
			_formulaeArray = [[BPHomebrewManager sharedManager] allFormulae];
			break;
			
		case kBPListInstalled:
			_formulaeArray = [[BPHomebrewManager sharedManager] installedFormulae];
			break;
			
		case kBPListLeaves:
			_formulaeArray = [[BPHomebrewManager sharedManager] leavesFormulae];
			break;

		case kBPListPinned:
			_formulaeArray = [[BPHomebrewManager sharedManager] pinnedFormulae];
			break;

		case kBPListInstalledCasks:
			_formulaeArray = [[BPHomebrewManager sharedManager] installedCasks];
			break;

		case kBPListOutdatedCasks:
			_formulaeArray = [[BPHomebrewManager sharedManager] outdatedCasks];
			break;

		case kBPListAllCasks:
			_formulaeArray = [[BPHomebrewManager sharedManager] allCasks];
			break;
			
		case kBPListOutdated:
			_formulaeArray = [[BPHomebrewManager sharedManager] outdatedFormulae];
			break;
			
		case kBPListSearch:
			_formulaeArray = [[BPHomebrewManager sharedManager] searchFormulae];
			break;
			
		case kBPListRepositories:
			_formulaeArray = [[BPHomebrewManager sharedManager] repositoriesFormulae];
			
		default:
			break;
	}

	if (self.sortDescriptors.count > 0)
	{
		_formulaeArray = [BPFormulaeDataSource formulae:_formulaeArray sortedBy:self.sortDescriptors];
	}
}


#pragma mark - NSTableView DataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
	return [self.formulaeArray count];
}

- (BPFormula *)formulaAtIndex:(NSInteger)index
{
	if ([self.formulaeArray count] > index && index >= 0) {
		return [self.formulaeArray objectAtIndex:index];
	}
	return nil;
}

- (NSInteger)indexOfFormulaNamed:(NSString *)name
{
	if (name.length == 0)
	{
		return -1;
	}

	NSUInteger index = [self.formulaeArray indexOfObjectPassingTest:^BOOL(BPFormula *formula, NSUInteger idx, BOOL *stop) {
		return [formula.name isEqualToString:name];
	}];

	return (index == NSNotFound) ? -1 : (NSInteger)index;
}

+ (NSComparisonResult)compareFormula:(BPFormula *)lhs
						  toFormula:(BPFormula *)rhs
							 forKey:(NSString *)key
{
	if ([key isEqualToString:kColumnIdentifierName])
	{
		return [lhs.name localizedCaseInsensitiveCompare:rhs.name];
	}

	if ([key isEqualToString:kColumnIdentifierStatus])
	{
		// Enum order, not the localized label: not installed < installed <
		// outdated, the same in every language.
		BPHomebrewManager *manager = [BPHomebrewManager sharedManager];
		BPFormulaStatus left = [manager statusForFormula:lhs];
		BPFormulaStatus right = [manager statusForFormula:rhs];
		if (left == right) return NSOrderedSame;
		return (left < right) ? NSOrderedAscending : NSOrderedDescending;
	}

	NSString *leftValue = [key isEqualToString:kColumnIdentifierLatestVersion] ? lhs.shortLatestVersion : lhs.version;
	NSString *rightValue = [key isEqualToString:kColumnIdentifierLatestVersion] ? rhs.shortLatestVersion : rhs.version;

	// An absent version (every row under All Formulae) sorts first rather than
	// comparing arbitrarily against rows that have one.
	if (leftValue.length == 0 && rightValue.length == 0) return NSOrderedSame;
	if (leftValue.length == 0) return NSOrderedAscending;
	if (rightValue.length == 0) return NSOrderedDescending;

	// Natural ordering, so 9.0 precedes 10.0 instead of following it.
	return [leftValue localizedStandardCompare:rightValue];
}

+ (NSArray<BPFormula *> *)formulae:(NSArray<BPFormula *> *)formulae
						  sortedBy:(NSArray<NSSortDescriptor *> *)descriptors
{
	NSSortDescriptor *descriptor = descriptors.firstObject;
	if (!descriptor.key)
	{
		return formulae ?: @[];
	}

	// sortedArrayUsingComparator: is not guaranteed stable, so sort indices and
	// break ties by original position.
	NSArray<NSNumber *> *positions = [self indexesForCount:formulae.count];
	NSArray<NSNumber *> *ordered = [positions sortedArrayUsingComparator:^NSComparisonResult(NSNumber *l, NSNumber *r) {
		NSComparisonResult result = [self compareFormula:formulae[l.unsignedIntegerValue]
											   toFormula:formulae[r.unsignedIntegerValue]
												  forKey:descriptor.key];
		if (result == NSOrderedSame)
		{
			return [l compare:r];
		}
		return descriptor.ascending ? result : (result == NSOrderedAscending ? NSOrderedDescending : NSOrderedAscending);
	}];

	NSMutableArray<BPFormula *> *sorted = [NSMutableArray arrayWithCapacity:formulae.count];
	for (NSNumber *position in ordered)
	{
		[sorted addObject:formulae[position.unsignedIntegerValue]];
	}
	return sorted;
}

+ (NSArray<NSNumber *> *)indexesForCount:(NSUInteger)count
{
	NSMutableArray<NSNumber *> *indexes = [NSMutableArray arrayWithCapacity:count];
	for (NSUInteger i = 0; i < count; i++)
	{
		[indexes addObject:@(i)];
	}
	return indexes;
}

- (NSArray *)formulasAtIndexSet:(NSIndexSet *)indexSet
{
	if (indexSet.count > 0 && [self.formulaeArray count] > indexSet.lastIndex) {
		return [self.formulaeArray objectsAtIndexes:indexSet];
	}
	return nil;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	// the return value is typed as (id) because it will return a string in all cases with the exception of the
	if(self.formulaeArray) {
		NSString *columnIdentifer = [tableColumn identifier];
		id element = [self.formulaeArray objectAtIndex:(NSUInteger)row];
		
		// Compare each column identifier and set the return value to
		// the Person field value appropriate for the column.
		if ([columnIdentifer isEqualToString:kColumnIdentifierName]) {
			if ([element isKindOfClass:[BPFormula class]]) {
				BOOL pinned = [[BPHomebrewManager sharedManager] isFormulaPinned:element];
				return [BPFormulaeDataSource nameCellValueForFormula:element pinned:pinned];
			} else {
				return element;
			}
		} else if ([columnIdentifer isEqualToString:kColumnIdentifierVersion]) {
			if ([element isKindOfClass:[BPFormula class]]) {
				return [(BPFormula*)element version];
			} else {
				return element;
			}
		} else if ([columnIdentifer isEqualToString:kColumnIdentifierLatestVersion]) {
			if ([element isKindOfClass:[BPFormula class]]) {
				return [(BPFormula*)element shortLatestVersion];
			} else {
				return element;
			}
		} else if ([columnIdentifer isEqualToString:kColumnIdentifierStatus]) {
			if ([element isKindOfClass:[BPFormula class]]) {
				switch ([[BPHomebrewManager sharedManager] statusForFormula:element]) {
					case kBPFormulaInstalled:
						return NSLocalizedString(@"Formula_Status_Installed", nil);
						
					case kBPFormulaNotInstalled:
						return NSLocalizedString(@"Formula_Status_Not_Installed", nil);
						
					case kBPFormulaOutdated:
						return NSLocalizedString(@"Formula_Status_Outdated", nil);
						
					default:
						return @"";
				}
			} else {
				return element;
			}
		}
	}
	
	return @"";
}

@end
