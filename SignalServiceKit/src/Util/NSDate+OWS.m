//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "NSDate+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@implementation NSDate (millisecondTimeStamp)

+ (uint64_t)ows_millisecondTimeStamp
{
    NSDate *now = [self new];
    return (uint64_t)(now.timeIntervalSince1970 * 1000);
}

+ (NSDate *)ows_dateWithMillisecondsSince1970:(uint64_t)milliseconds
{
    return [NSDate dateWithTimeIntervalSince1970:(milliseconds / 1000.0)];
}

+ (uint64_t)ows_millisecondsSince1970ForDate:(NSDate *)date
{
    return (uint64_t)(date.timeIntervalSince1970 * 1000);
}

@end

NS_ASSUME_NONNULL_END
