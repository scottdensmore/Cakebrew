#import "BPServiceDetails.h"
#import "BPService.h"

@implementation BPServiceDetails
+ (NSURL *)readableFileURLForPath:(NSString *)path
{
	if (![path isKindOfClass:NSString.class] || !path.length ||
		[path rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound ||
		[path hasPrefix:@"//"] || (![path hasPrefix:@"/"] && ![path hasPrefix:@"~/"])) return nil;
	NSString *resolved = path.stringByExpandingTildeInPath.stringByStandardizingPath.stringByResolvingSymlinksInPath;
	NSFileManager *files = NSFileManager.defaultManager;
	NSDictionary *attributes = [files attributesOfItemAtPath:resolved error:nil];
	if (![attributes[NSFileType] isEqual:NSFileTypeRegular] || ![files isReadableFileAtPath:resolved]) return nil;
	return [NSURL fileURLWithPath:resolved];
}
+ (instancetype)detailsForName:(NSString *)name output:(NSString *)output succeeded:(BOOL)succeeded
{
	BPServiceDetails *result = [self new];
	result->_rawOutput = [output copy] ?: @"";
	if (!succeeded || !name.length) return result;
	id records = [NSJSONSerialization JSONObjectWithData:[result.rawOutput dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
	if (![records isKindOfClass:NSArray.class] || [records count] != 1) return result;
	id record = [records firstObject];
	if (![record isKindOfClass:NSDictionary.class] || ![record[@"name"] isEqual:name]) return result;
	result->_service = [BPService servicesFromJSONString:output].firstObject;
	result->_serviceFile = [self stringOrNil:record[@"file"]];
	result->_loadedFile = [self stringOrNil:record[@"loaded_file"]];
	result->_logPath = [self stringOrNil:record[@"log_path"]];
	result->_errorLogPath = [self stringOrNil:record[@"error_log_path"]];
	result->_exitCode = [self integerOrNil:record[@"exit_code"]];
	NSNumber *pid = [self integerOrNil:record[@"pid"]];
	result.service.pid = pid.longLongValue > 0 ? pid : nil;
	result->_available = result.service != nil;
	return result;
}
+ (NSString *)stringOrNil:(id)value
{
	return [value isKindOfClass:NSString.class] ? [value copy] : nil;
}
+ (NSNumber *)integerOrNil:(id)value
{
	if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()) return nil;
	return [value doubleValue] == [value longLongValue] ? value : nil;
}
@end
