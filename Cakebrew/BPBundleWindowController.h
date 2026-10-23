#import <Cocoa/Cocoa.h>
#import "BPFormulaInformation-Swift.h"

@interface BPBundleWindowController (OutPointerBridge)

+ (BPBrewfileReviewHost *)reviewHostForPlan:(BPBrewfilePlan *)plan
                                   fileName:(NSString *)fileName
                                      error:(NSError *)error
                            entriesTextView:(NSTextView * __autoreleasing *)outTextView;

@end
