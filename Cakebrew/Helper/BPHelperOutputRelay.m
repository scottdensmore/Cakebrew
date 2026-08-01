//
//  BPHelperOutputRelay.m
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

#import "BPHelperOutputRelay.h"

@implementation BPHelperOutputRelay
{
	NSMutableData *_accumulated;
	NSMutableData *_undecoded;   // trailing bytes of a split UTF-8 sequence
	void (^_sink)(NSString *);
}

- (instancetype)initWithSink:(void (^)(NSString *))sink
{
	self = [super init];
	if (self)
	{
		_accumulated = [NSMutableData data];
		_undecoded = [NSMutableData data];
		_sink = [sink copy];
	}
	return self;
}

- (void)appendData:(NSData *)data
{
	if (data.length == 0)
	{
		return;
	}

	@synchronized (self)
	{
		[_accumulated appendData:data];

		// A pipe read can split a multi-byte character (brew prints ✔/✘/→), so
		// hold bytes that don't yet decode until the rest arrives.
		[_undecoded appendData:data];
		NSString *chunk = [[NSString alloc] initWithData:_undecoded encoding:NSUTF8StringEncoding];
		if (!chunk)
		{
			return;
		}
		[_undecoded setLength:0];

		// Forwarded inside the lock so chunks reach the sink in order; the sink
		// is an async XPC proxy call, so this doesn't block on the peer.
		if (_sink && chunk.length > 0)
		{
			_sink(chunk);
		}
	}
}

- (NSString *)accumulatedOutput
{
	@synchronized (self)
	{
		return [[NSString alloc] initWithData:_accumulated encoding:NSUTF8StringEncoding] ?: @"";
	}
}

@end
