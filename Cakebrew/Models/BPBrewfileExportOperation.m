#import "BPBrewfileExportOperation.h"
#import "BPHomebrewInterface.h"

@interface BPBrewfileExportOperation ()
@property (copy) NSURL *url;
@property (strong) BPHomebrewInterface *interface;
@property (readwrite, getter=isRunning) BOOL running;
@property BOOL started;
@end

@implementation BPBrewfileExportOperation
+ (NSURL *)exportURLForSaveResponse:(NSModalResponse)response URL:(NSURL *)url
{
 return response == NSModalResponseOK && url.isFileURL ? url : nil;
}

- (instancetype)initWithURL:(NSURL *)url interface:(BPHomebrewInterface *)interface
{
 if ((self = [super init])) { _url = [url copy]; _interface = interface; }
 return self;
}

- (void)startWithCompletion:(void (^)(NSError *))completion
{
 NSAssert(NSThread.isMainThread, @"Export starts on the main thread");
 if (self.started) return;
 self.started = YES;
 self.running = YES;
 dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
  NSError *error = [self.interface runBrewExportToolWithPath:self.url.path];
  dispatch_async(dispatch_get_main_queue(), ^{
   self.running = NO;
   if (completion) completion(error);
  });
 });
}
@end
