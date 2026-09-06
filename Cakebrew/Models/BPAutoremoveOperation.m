#import "BPAutoremoveOperation.h"
#import "BPAutoremovePreview.h"
#import "BPHomebrewInterface.h"

@interface BPAutoremoveOperation ()
@property (strong) BPAutoremovePreview *preview;
@property (strong) BPHomebrewInterface *interface;
@property (strong) NSProgress *progress;
@property (readwrite, getter=isRunning) BOOL running;
@property BOOL started;
@property BOOL workerFinished;
@end
@implementation BPAutoremoveOperation
- (instancetype)initWithPreview:(BPAutoremovePreview *)preview interface:(BPHomebrewInterface *)interface
{
	if ((self = [super init])) { _preview = preview; _interface = interface; _progress = [NSProgress progressWithTotalUnitCount:1]; }
	return self;
}
- (void)startWithOutput:(void (^)(NSString *))output completion:(void (^)(BOOL, BOOL, BOOL, NSString *))completion
{
	@synchronized (self) { if (self.started) return; self.started = YES; self.running = YES; }
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		BOOL success = NO, attempted = NO;
		NSString *message = NSLocalizedString(@"The unused dependency list changed or could not be verified. Nothing was removed. Close this window and review a new preview.", nil);
		if (self.interface.brewTransport == kBPBrewTransportDirect && self.preview.valid && self.preview.names.count && !self.progress.cancelled) {
			BPAutoremovePreview *fresh = [self.interface previewAutoremoveWithProgress:self.progress];
			if (output && fresh.rawOutput.length) dispatch_async(dispatch_get_main_queue(), ^{ output(fresh.rawOutput); });
			if (fresh.valid && [[NSSet setWithArray:fresh.names] isEqualToSet:[NSSet setWithArray:self.preview.names]] && !self.progress.cancelled) {
				attempted = YES;
				success = [self.interface removeUnusedFormulae:self.preview.names progress:self.progress output:^(NSString *chunk) {
					if (output) dispatch_async(dispatch_get_main_queue(), ^{ output(chunk); });
				}];
				message = success ? NSLocalizedString(@"Reviewed unused dependencies were removed.", nil) : NSLocalizedString(@"Removal failed. Packages may have been partially removed. The formula and service lists will be refreshed.", nil);
			}
		}
		BOOL cancelled;
		@synchronized (self.progress) {
			self.workerFinished = YES;
			cancelled = self.progress.cancelled;
		}
		if (cancelled) message = attempted ? NSLocalizedString(@"Removal cancelled. Packages may have been partially removed. The formula and service lists will be refreshed.", nil) : NSLocalizedString(@"Cancelled before removal. Nothing was removed.", nil);
		dispatch_async(dispatch_get_main_queue(), ^{
			self.running = NO;
			if (completion) completion(success && !cancelled, cancelled, attempted, message);
		});
	});
}
- (void)cancel
{
	@synchronized (self.progress) { if (!self.workerFinished) [self.progress cancel]; }
}
@end
