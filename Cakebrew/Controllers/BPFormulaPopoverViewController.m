#import "BPFormulaPopoverViewController.h"

@implementation BPFormulaPopoverViewController (TypedFormula)

- (BPFormula *)formula {
	return (BPFormula *)[self formulaObject];
}

- (void)setFormula:(BPFormula *)formula {
	[self setFormulaObject:formula];
}

@end
