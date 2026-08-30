//
//  BPService.m
//  Cakebrew
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU General Public License as published by
//	the Free Software Foundation, either version 3 of the License, or
//	(at your option) any later version.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.	See the
//	GNU General Public License for more details.
//
//	You should have received a copy of the GNU General Public License
//	along with this program.	If not, see <http://www.gnu.org/licenses/>.
//

#import "BPService.h"

@implementation BPService

+ (NSArray<BPService *> *)servicesFromJSONString:(NSString *)output
{
	NSData *data = [output dataUsingEncoding:NSUTF8StringEncoding];
	if (!data)
	{
		return @[];
	}

	id parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![parsed isKindOfClass:[NSArray class]])
	{
		return @[];
	}

	NSMutableArray<BPService *> *services = [NSMutableArray array];
	for (id entry in (NSArray *)parsed)
	{
		if (![entry isKindOfClass:[NSDictionary class]])
		{
			continue;
		}
		BPService *service = [BPService serviceWithDictionary:entry];
		if (service)
		{
			[services addObject:service];
		}
	}
	return services;
}

+ (instancetype)serviceWithDictionary:(NSDictionary *)dict
{
	NSString *name = [self stringOrNil:dict[@"name"]];
	if (name.length == 0)
	{
		return nil;
	}

	BPService *service = [[BPService alloc] init];
	service.name = name;
	service.user = [self stringOrNil:dict[@"user"]];
	service.statusString = [self stringOrNil:dict[@"status"]];
	service.status = [self statusFromString:service.statusString];

	id pid = dict[@"pid"];
	service.pid = [pid isKindOfClass:[NSNumber class]] ? pid : nil;

	return service;
}

+ (NSString *)stringOrNil:(id)value
{
	return [value isKindOfClass:[NSString class]] ? value : nil;
}

+ (NSString *)localizationKeyForStatus:(BPServiceStatus)status
{
	switch (status)
	{
		case kBPServiceStatusNone:      return @"Services_Status_None";
		case kBPServiceStatusStarted:   return @"Services_Status_Started";
		case kBPServiceStatusStopped:   return @"Services_Status_Stopped";
		case kBPServiceStatusError:     return @"Services_Status_Error";
		case kBPServiceStatusScheduled: return @"Services_Status_Scheduled";
		case kBPServiceStatusUnknown:   break;
	}
	return @"Services_Status_Unknown";
}

+ (NSString *)localizedNameForStatus:(BPServiceStatus)status
{
	return NSLocalizedString([self localizationKeyForStatus:status], nil);
}

+ (BPServiceStatus)statusFromString:(NSString *)status
{
	static NSDictionary<NSString *, NSNumber *> *map;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		map = @{ @"none":      @(kBPServiceStatusNone),
				 @"started":   @(kBPServiceStatusStarted),
				 @"stopped":   @(kBPServiceStatusStopped),
				 @"error":     @(kBPServiceStatusError),
				 @"scheduled": @(kBPServiceStatusScheduled) };
	});

	NSNumber *mapped = status ? map[status] : nil;
	return mapped ? mapped.integerValue : kBPServiceStatusUnknown;
}

@end
