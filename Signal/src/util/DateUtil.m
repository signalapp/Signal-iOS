//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "DateUtil.h"
#import <SignalServiceKit/NSDate+OWS.h>

static NSString *const DATE_FORMAT_WEEKDAY = @"EEEE";

@implementation DateUtil

+ (NSDateFormatter *)dateFormatter {
    NSDateFormatter *formatter = [NSDateFormatter new];
    [formatter setLocale:[NSLocale currentLocale]];
    [formatter setTimeStyle:NSDateFormatterNoStyle];
    [formatter setDateStyle:NSDateFormatterShortStyle];
    return formatter;
}

+ (NSDateFormatter *)weekdayFormatter {
    NSDateFormatter *formatter = [NSDateFormatter new];
    [formatter setLocale:[NSLocale currentLocale]];
    [formatter setDateFormat:DATE_FORMAT_WEEKDAY];
    return formatter;
}

+ (NSDateFormatter *)timeFormatter {
    NSDateFormatter *formatter = [NSDateFormatter new];
    [formatter setLocale:[NSLocale currentLocale]];
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    [formatter setDateStyle:NSDateFormatterNoStyle];
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

@end
