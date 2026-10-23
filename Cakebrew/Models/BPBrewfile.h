#import <Foundation/Foundation.h>
#import "BPFormulaInformation-Swift.h"

NS_ASSUME_NONNULL_BEGIN

@interface BPBrewfile (BPLocalizedFilename)
+ (NSString *)defaultFilename __attribute__((annotate("returns_localized_nsstring")));
@end

NS_ASSUME_NONNULL_END
