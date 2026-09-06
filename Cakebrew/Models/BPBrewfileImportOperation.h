#import <Foundation/Foundation.h>
@class BPBrewfilePlan, BPHomebrewInterface;

/// One-shot operation. The reviewed snapshot is retained until command exit.
@interface BPBrewfileImportOperation : NSObject
@property (readonly, getter=isRunning) BOOL running;
- (instancetype)initWithPlan:(BPBrewfilePlan *)plan interface:(BPHomebrewInterface *)interface;
- (void)startWithOutput:(void (^)(NSString *))output completion:(void (^)(BOOL success, BOOL cancelled, NSError *error))completion;
- (void)cancel;
@end
