#import <Cocoa/Cocoa.h>
@class BPHomebrewInterface;

/// One-shot export. Start and observe on main; the command runs off main.
@interface BPBrewfileExportOperation : NSObject
@property (readonly, getter=isRunning) BOOL running;
+ (NSURL *)exportURLForSaveResponse:(NSModalResponse)response URL:(NSURL *)url;
- (instancetype)initWithURL:(NSURL *)url interface:(BPHomebrewInterface *)interface;
- (void)startWithCompletion:(void (^)(NSError *error))completion;
@end
