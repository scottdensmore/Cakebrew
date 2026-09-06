#import "BPBrewfileImportOperation.h"
#import "BPBrewfilePlan.h"
#import "BPHomebrewInterface.h"

@interface BPBrewfileImportOperation ()
@property (strong) BPBrewfilePlan *plan;
@property (strong) BPHomebrewInterface *interface;
@property (strong) NSProgress *progress;
@property (readwrite, getter=isRunning) BOOL running;
@property BOOL started;
@end
@implementation BPBrewfileImportOperation
- (instancetype)initWithPlan:(BPBrewfilePlan *)plan interface:(BPHomebrewInterface *)interface
{
 if ((self = [super init])) { _plan = plan; _interface = interface; _progress = [NSProgress progressWithTotalUnitCount:1]; }
 return self;
}
- (void)startWithOutput:(void (^)(NSString *))output completion:(void (^)(BOOL, BOOL, NSError *))completion
{
 @synchronized (self) { if (self.started) return; self.started = YES; self.running = YES; }
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
  NSError *error = nil; NSURL *snapshot = nil; BOOL success = NO;
  if (self.interface.brewTransport != kBPBrewTransportDirect) {
   error = [NSError errorWithDomain:@"Cakebrew.Brewfile" code:1 userInfo:@{NSLocalizedDescriptionKey: NSLocalizedString(@"Reviewed import requires the standard, non-sandboxed Cakebrew app. Helper transport is not supported.", nil)}];
  } else if (!self.progress.cancelled && self.plan.canInstall) {
   snapshot = [self.plan createSnapshotWithError:&error];
   if (snapshot && !self.progress.cancelled) {
    success = [self.interface runBrewImportToolWithPath:snapshot.path progress:self.progress withReturnsBlock:^(NSString *chunk) {
     if (output) dispatch_async(dispatch_get_main_queue(), ^{ output(chunk); });
    }];
   }
  }
  [BPBrewfilePlan removeSnapshot:snapshot];
  dispatch_async(dispatch_get_main_queue(), ^{
   self.running = NO;
   if (completion) completion(success && !self.progress.cancelled, self.progress.cancelled, error);
  });
 });
}
- (void)cancel
{
 @synchronized (self.progress) {
  if (!self.started || self.running) [self.progress cancel];
 }
}
@end
