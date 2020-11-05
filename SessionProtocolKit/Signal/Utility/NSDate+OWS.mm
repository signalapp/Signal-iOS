//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "NSDate+OWS.h"
#import <chrono>

NS_ASSUME_NONNULL_BEGIN

const NSTimeInterval kSecondInterval = 1;
const NSTimeInterval kMinuteInterval = 60;
const NSTimeInterval kHourInterval = 60 * kMinuteInterval;
const NSTimeInterval kDayInterval = 24 * kHourInterval;
const NSTimeInterval kWeekInterval = 7 * kDayInterval;
const NSTimeInterval kMonthInterval = 30 * kDayInterval;
const NSTimeInterval kYearInterval = 365 * kDayInterval;

@implementation NSDate (OWS)

+ (uint64_t)ows_millisecondTimeStamp
{
    uint64_t milliseconds
        = (uint64_t)(std::chrono::system_clock::now().time_since_epoch() / std::chrono::milliseconds(1));
    return milliseconds;
}

+ (NSDate *)ows_dateWithMillisecondsSince1970:(uint64_t)milliseconds
{
    return [NSDate dateWithTimeIntervalSince1970:(milliseconds / 1000.0)];
}

+ (uint64_t)ows_millisecondsSince1970ForDate:(NSDate *)date
{
    return (uint64_t)(date.timeIntervalSince1970 * 1000);
}

- (BOOL)isAfterDate:(NSDate *)otherDate
{
    return [self compare:otherDate] == NSOrderedDescending;
}

- (BOOL)isBeforeDate:(NSDate *)otherDate
{
    return [self compare:otherDate] == NSOrderedAscending;
}

- (BOOL)isAfterNow
{
    return [self isAfterDate:[NSDate new]];
}

- (BOOL)isBeforeNow
{
    return [self isBeforeDate:[NSDate new]];
}

@end

NS_ASSUME_NONNULL_END
