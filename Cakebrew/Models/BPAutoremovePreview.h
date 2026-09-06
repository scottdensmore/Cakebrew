#import <Foundation/Foundation.h>

/// Strict, immutable interpretation of Homebrew's dry-run output.
@interface BPAutoremovePreview : NSObject
@property (readonly) BOOL valid;
@property (copy, readonly) NSArray<NSString *> *names;
@property (copy, readonly) NSString *rawOutput;
+ (instancetype)previewWithOutput:(NSString *)output succeeded:(BOOL)succeeded;
@end
