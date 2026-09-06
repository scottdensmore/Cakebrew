#import "BPBrewfilePlan.h"
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>

@interface BPBrewfileEntry ()
@property (copy, readwrite) NSString *kind;
@property (copy, readwrite) NSString *name;
@property (copy, readwrite) NSString *status;
@property (copy) NSString *appStoreID;
@end
@implementation BPBrewfileEntry
@end

@interface BPBrewfilePlan ()
@property (copy, readwrite) NSArray<BPBrewfileEntry *> *entries;
@property (copy, readwrite) NSArray<NSString *> *diagnostics;
@property (copy, readwrite) NSString *canonicalContents;
@end

@implementation BPBrewfilePlan

+ (instancetype)planWithURL:(NSURL *)url inventories:(NSDictionary *)inventories error:(NSError *__autoreleasing *)error
{
 const NSUInteger limit = 1024 * 1024;
 int descriptor = url.isFileURL ? open(url.fileSystemRepresentation, O_RDONLY | O_NONBLOCK) : -1;
 struct stat info;
 NSMutableData *data = [NSMutableData data];
 BOOL valid = descriptor >= 0 && fstat(descriptor, &info) == 0 && S_ISREG(info.st_mode) && info.st_size <= limit;
 if (valid) {
  char buffer[8192]; ssize_t count = -1;
  while (data.length <= limit && (count = read(descriptor, buffer, sizeof(buffer))) > 0) [data appendBytes:buffer length:(NSUInteger)count];
  valid = count == 0 && data.length <= limit;
 }
 if (descriptor >= 0) close(descriptor);
 NSString *contents = valid ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
 if (!contents) {
  if (error) *error = [NSError errorWithDomain:@"Cakebrew.Brewfile" code:2 userInfo:@{NSLocalizedDescriptionKey:NSLocalizedString(@"Choose a readable UTF-8 Brewfile smaller than 1 MiB. Nothing was installed.", nil)}];
  return nil;
 }
 return [self planWithString:contents inventories:inventories];
}

+ (BOOL)string:(NSString *)string matches:(NSString *)pattern
{
 NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:NULL];
 return [regex numberOfMatchesInString:string options:0 range:NSMakeRange(0, string.length)] == 1;
}

+ (instancetype)planWithString:(NSString *)contents inventories:(NSDictionary<NSString *,NSArray<NSString *> *> *)inventories
{
 BPBrewfilePlan *plan = [self new];
 NSMutableArray *entries = [NSMutableArray array], *diagnostics = [NSMutableArray array];
 NSMutableString *canonical = [NSMutableString string];
 // No Ruby evaluator, shell, unescaping, interpolation, or option parsing.
 NSRegularExpression *literal = [NSRegularExpression regularExpressionWithPattern:@"\\A[ \\t]*(brew|cask|tap|mas|vscode)[ \\t]+(['\"])([^'\"\\\\\\r\\n]+)\\2(?:[ \\t]*,[ \\t]*id:[ \\t]*([1-9][0-9]*))?[ \\t]*(?:#[^\\r\\n]*)?\\z" options:0 error:NULL];
 NSArray *lines = [[contents stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"] componentsSeparatedByString:@"\n"];
 [lines enumerateObjectsUsingBlock:^(NSString *line, NSUInteger index, BOOL *stop) {
  if ([self string:line matches:@"\\A[ \\t]*(?:#[^\\r\\n]*)?\\z"]) return;
  NSTextCheckingResult *match = [literal firstMatchInString:line options:0 range:NSMakeRange(0, line.length)];
  NSString *kind = match ? [line substringWithRange:[match rangeAtIndex:1]] : nil;
  NSString *name = match ? [line substringWithRange:[match rangeAtIndex:3]] : nil;
  NSString *identifier = match && [match rangeAtIndex:4].location != NSNotFound ? [line substringWithRange:[match rangeAtIndex:4]] : nil;
  BOOL valid = match != nil;
  if ([kind isEqualToString:@"mas"]) {
   valid = valid && identifier && identifier.length <= 18 && [self string:name matches:@"\\A[A-Za-z0-9][A-Za-z0-9 ._()+&:!-]*\\z"];
  } else {
   valid = valid && !identifier;
   NSString *component = @"[a-zA-Z0-9][a-zA-Z0-9_+@.-]*";
   NSString *pattern = [kind isEqualToString:@"tap"] ? [NSString stringWithFormat:@"\\A%@/%@\\z", component, component] :
    [kind isEqualToString:@"vscode"] ? @"\\A[a-zA-Z0-9][a-zA-Z0-9-]*\\.[a-zA-Z0-9][a-zA-Z0-9-]*\\z" :
    [NSString stringWithFormat:@"\\A%@(?:/%@/%@)?\\z", component, component, component];
   valid = valid && [self string:name matches:pattern];
  }
  if (!valid) {
   [diagnostics addObject:[NSString localizedStringWithFormat:NSLocalizedString(@"Line %lu: unsupported syntax or invalid package name. Nothing will be installed.", nil), index + 1]];
   return;
  }
  BPBrewfileEntry *entry = [BPBrewfileEntry new]; entry.kind = kind; entry.name = name; entry.appStoreID = identifier;
  NSArray *inventory = inventories[kind];
  BOOL qualified = ![kind isEqualToString:@"tap"] && [name containsString:@"/"];
  entry.status = !inventory || [@[@"mas", @"vscode"] containsObject:kind] || qualified ? @"Not checked" :
   [inventory containsObject:name] ? @"Installed" : @"Missing";
  [entries addObject:entry];
  [canonical appendFormat:@"%@ '%@'%@\n", kind, name, identifier ? [@", id: " stringByAppendingString:identifier] : @""];
 }];
 plan.entries = entries; plan.diagnostics = diagnostics;
 if (entries.count && !diagnostics.count) plan.canonicalContents = canonical;
 return plan;
}

- (BOOL)canInstall { return self.canonicalContents.length > 0 && self.diagnostics.count == 0; }

- (NSString *)reviewText
{
 NSMutableString *text = [NSMutableString string];
 NSUInteger installed = 0, missing = 0, unchecked = 0;
 for (BPBrewfileEntry *entry in self.entries) {
  if ([entry.status isEqualToString:@"Installed"]) installed++;
  else if ([entry.status isEqualToString:@"Missing"]) missing++;
  else unchecked++;
 }
 [text appendFormat:NSLocalizedString(@"%lu installed • %lu missing • %lu not checked", nil), installed, missing, unchecked];
 [text appendString:@"\n\n"];
 NSArray *kinds = @[@"brew", @"cask", @"tap", @"mas", @"vscode"];
 NSArray *titles = @[NSLocalizedString(@"Formulae", nil), NSLocalizedString(@"Casks", nil), NSLocalizedString(@"Taps", nil), NSLocalizedString(@"Mac App Store", nil), NSLocalizedString(@"VS Code", nil)];
 for (NSUInteger i = 0; i < kinds.count; i++) {
  NSMutableArray *lines = [NSMutableArray array];
  for (BPBrewfileEntry *entry in self.entries) if ([entry.kind isEqualToString:kinds[i]]) {
   NSString *status = [entry.status isEqualToString:@"Installed"] ? NSLocalizedString(@"Installed", nil) : [entry.status isEqualToString:@"Missing"] ? NSLocalizedString(@"Missing", nil) : NSLocalizedString(@"Not checked", nil);
   NSString *name = entry.appStoreID ? [NSString stringWithFormat:@"%@ (id: %@)", entry.name, entry.appStoreID] : entry.name;
   [lines addObject:[NSString stringWithFormat:@"%@ — %@", name, status]];
  }
  if (lines.count) [text appendFormat:@"%@\n%@\n\n", titles[i], [lines componentsJoinedByString:@"\n"]];
 }
 if (self.diagnostics.count) [text appendString:[self.diagnostics componentsJoinedByString:@"\n"]];
 else if (!self.entries.count) [text appendString:NSLocalizedString(@"No supported package entries. Nothing will be installed.", nil)];
 return text;
}

- (NSURL *)createSnapshotWithError:(NSError *__autoreleasing *)error
{
 if (!self.canInstall) return nil;
 NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:@"cakebrew-reviewed-XXXXXX"];
 char *buffer = strdup(template.fileSystemRepresentation);
 char *directory = mkdtemp(buffer);
 NSURL *url = directory ? [[NSURL fileURLWithFileSystemRepresentation:directory isDirectory:YES relativeToURL:nil] URLByAppendingPathComponent:@"Brewfile"] : nil;
 free(buffer);
 if (!url) { if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil]; return nil; }
 NSData *data = [self.canonicalContents dataUsingEncoding:NSUTF8StringEncoding];
 if (![[NSFileManager defaultManager] createFileAtPath:url.path contents:data attributes:@{NSFilePosixPermissions: @0400}]) {
  if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileWriteUnknownError userInfo:nil];
  [BPBrewfilePlan removeSnapshot:url]; return nil;
 }
 return url;
}

+ (void)removeSnapshot:(NSURL *)snapshot
{
 if (snapshot && [snapshot.lastPathComponent isEqualToString:@"Brewfile"] && [snapshot.URLByDeletingLastPathComponent.lastPathComponent hasPrefix:@"cakebrew-reviewed-"])
  [[NSFileManager defaultManager] removeItemAtURL:snapshot.URLByDeletingLastPathComponent error:NULL];
}
@end
