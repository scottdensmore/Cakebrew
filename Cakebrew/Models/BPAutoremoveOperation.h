#import <Foundation/Foundation.h>
@class BPAutoremovePreview, BPHomebrewInterface;
@interface BPAutoremoveOperation : NSObject
@property (readonly, getter=isRunning) BOOL running;
- (instancetype)initWithPreview:(BPAutoremovePreview *)preview interface:(BPHomebrewInterface *)interface;
- (void)startWithOutput:(void (^)(NSString *))output completion:(void (^)(BOOL success, BOOL cancelled, BOOL mutationAttempted, NSString *message))completion;
- (void)cancel;
@end
