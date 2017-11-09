//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DateUtil.h"
#import <SignalServiceKit/NSDate+OWS.h>

static NSString *const DATE_FORMAT_WEEKDAY = @"EEEE";

@implementation DateUtil

+ (NSDateFormatter *)dateFormatter {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setTimeStyle:NSDateFormatterNoStyle];
        [formatter setDateStyle:NSDateFormatterShortStyle];
    });
    return formatter;
}

+ (NSDateFormatter *)weekdayFormatter {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setDateFormat:DATE_FORMAT_WEEKDAY];
    });
    return formatter;
}

+ (NSDateFormatter *)timeFormatter {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setTimeStyle:NSDateFormatterShortStyle];
        [formatter setDateStyle:NSDateFormatterNoStyle];
    });
    return formatter;
}

+ (BOOL)dateIsOlderThanOneDay:(NSDate *)date {
    return [[NSDate date] timeIntervalSinceDate:date] > kDayInterval;
}

+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date {
    return [[NSDate date] timeIntervalSinceDate:date] > kWeekInterval;
}

+ (BOOL)date:(NSDate *)date isEqualToDateIgnoringTime:(NSDate *)anotherDate {
    static const unsigned componentFlags = (NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay);
    NSDateComponents *components1 = [[NSCalendar autoupdatingCurrentCalendar] components:componentFlags fromDate:date];
    NSDateComponents *components2 =
        [[NSCalendar autoupdatingCurrentCalendar] components:componentFlags fromDate:anotherDate];
    return ((components1.year == components2.year) && (components1.month == components2.month) &&
            (components1.day == components2.day));
}

+ (BOOL)dateIsToday:(NSDate *)date {
    return [self date:[NSDate date] isEqualToDateIgnoringTime:date];
}

+ (NSString *)formatPastTimestampRelativeToNow:(uint64_t)pastTimestamp
{
    OWSCAssert(pastTimestamp > 0);

    uint64_t nowTimestamp = [NSDate ows_millisecondTimeStamp];
    BOOL isFutureTimestamp = pastTimestamp >= nowTimestamp;

    NSDate *pastDate = [NSDate ows_dateWithMillisecondsSince1970:pastTimestamp];
    if (isFutureTimestamp || [self dateIsToday:pastDate]) {
        return [[self timeFormatter] stringFromDate:pastDate];
    } else if (![self dateIsOlderThanOneWeek:pastDate]) {
        return [[self weekdayFormatter] stringFromDate:pastDate];
    } else {
        return [[self dateFormatter] stringFromDate:pastDate];
    }
}

@end
