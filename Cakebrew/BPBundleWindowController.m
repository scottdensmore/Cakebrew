#import "BPBundleWindowController.h"

@implementation BPBundleWindowController (OutPointerBridge)

+ (BPBrewfileReviewHost *)reviewHostForPlan:(BPBrewfilePlan *)plan
                                   fileName:(NSString *)fileName
                                      error:(NSError *)error
                            entriesTextView:(NSTextView * __autoreleasing *)outTextView
{
    BPBrewfileReviewHost *host = [self reviewHostForPlan:plan fileName:fileName error:error];
    if (outTextView) {
        *outTextView = host.entriesTextView;
    }
    return host;
}

@end
