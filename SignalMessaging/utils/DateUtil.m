//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

#import "DateUtil.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalCoreKit/NSString+OWS.h>
#import <SignalMessaging/SignalMessaging-Swift.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const DATE_FORMAT_WEEKDAY = @"EEEE";

@implementation DateUtil

+ (NSDateFormatter *)dateFormatter
{
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

+ (NSDateFormatter *)weekdayFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setLocalizedDateFormatFromTemplate:DATE_FORMAT_WEEKDAY];
    });
    return formatter;
}

+ (NSDateFormatter *)monthAndDayFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setLocalizedDateFormatFromTemplate:@"M/d"];
    });
    return formatter;
}

+ (NSDateFormatter *)shortDayOfWeekFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        formatter.dateFormat = @"E";
    });
    return formatter;
}

+ (BOOL)dateIsOlderThanToday:(NSDate *)date
{
    return [self dateIsOlderThanToday:date now:[NSDate date]];
}

+ (BOOL)dateIsOlderThanToday:(NSDate *)date now:(NSDate *)now
{
    NSInteger dayDifference = [self daysFromFirstDate:date toSecondDate:now];
    return dayDifference > 0;
}

+ (BOOL)dateIsOlderThanYesterday:(NSDate *)date
{
    return [self dateIsOlderThanYesterday:date now:[NSDate date]];
}

+ (BOOL)dateIsOlderThanYesterday:(NSDate *)date now:(NSDate *)now
{
    NSInteger dayDifference = [self daysFromFirstDate:date toSecondDate:now];
    return dayDifference > 1;
}

+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date
{
    return [self dateIsOlderThanOneWeek:date now:[NSDate date]];
}

+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date now:(NSDate *)now
{
    NSInteger dayDifference = [self daysFromFirstDate:date toSecondDate:now];
    return dayDifference > 6;
}

+ (BOOL)dateIsToday:(NSDate *)date
{
    return [self dateIsToday:date now:[NSDate date]];
}

+ (BOOL)dateIsToday:(NSDate *)date now:(NSDate *)now
{
    NSInteger dayDifference = [self daysFromFirstDate:date toSecondDate:now];
    return dayDifference == 0;
}

+ (BOOL)dateIsThisYear:(NSDate *)date
{
    return [self dateIsThisYear:date now:[NSDate date]];
}

+ (BOOL)dateIsThisYear:(NSDate *)date now:(NSDate *)now
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    return (
        [calendar component:NSCalendarUnitYear fromDate:date] == [calendar component:NSCalendarUnitYear fromDate:now]);
}

+ (BOOL)dateIsYesterday:(NSDate *)date
{
    return [self dateIsYesterday:date now:[NSDate date]];
}

+ (BOOL)dateIsYesterday:(NSDate *)date now:(NSDate *)now
{
    NSInteger dayDifference = [self daysFromFirstDate:date toSecondDate:now];
    return dayDifference == 1;
}

+ (NSString *)formatPastTimestampRelativeToNow:(uint64_t)pastTimestamp
{
    OWSCAssertDebug(pastTimestamp > 0);

    uint64_t nowTimestamp = [NSDate ows_millisecondTimeStamp];
    BOOL isFutureTimestamp = pastTimestamp >= nowTimestamp;

    NSDate *pastDate = [NSDate ows_dateWithMillisecondsSince1970:pastTimestamp];
    NSString *dateString;
    if (isFutureTimestamp || [self dateIsToday:pastDate]) {
        dateString = OWSLocalizedString(@"DATE_TODAY", @"The current day.");
    } else if ([self dateIsYesterday:pastDate]) {
        dateString = OWSLocalizedString(@"DATE_YESTERDAY", @"The day before today.");
    } else {
        dateString = [[self dateFormatter] stringFromDate:pastDate];
    }
    return [[dateString stringByAppendingString:@" "]
        stringByAppendingString:[[self timeFormatter] stringFromDate:pastDate]];
}

+ (NSString *)formatTimestampShort:(uint64_t)timestamp
{
    return [self formatDateShort:[NSDate ows_dateWithMillisecondsSince1970:timestamp]];
}

+ (NSString *)formatDateShort:(NSDate *)date
{
    OWSAssertDebug(date);

    NSDate *now = [NSDate date];
    NSInteger dayDifference = [self daysFromFirstDate:date toSecondDate:now];
    BOOL dateIsOlderThanToday = dayDifference > 0;
    BOOL dateIsOlderThanOneWeek = dayDifference > 6;

    NSString *dateTimeString;
    if (![DateUtil dateIsThisYear:date]) {
        dateTimeString = [[DateUtil dateFormatter] stringFromDate:date];
    } else if (dateIsOlderThanOneWeek) {
        dateTimeString = [[DateUtil monthAndDayFormatter] stringFromDate:date];
    } else if (dateIsOlderThanToday) {
        dateTimeString = [[DateUtil shortDayOfWeekFormatter] stringFromDate:date];
    } else {
        dateTimeString = [DateUtil formatMessageTimestampForCVC:date.ows_millisecondsSince1970 shouldUseLongFormat:NO];
    }

    return dateTimeString;
}

+ (NSString *)formatTimestampAsTime:(uint64_t)timestamp
{
    return [self formatDateAsTime:[NSDate ows_dateWithMillisecondsSince1970:timestamp]];
}

+ (NSString *)formatDateAsTime:(NSDate *)date
{
    OWSAssertDebug(date);

    NSString *dateTimeString = [[DateUtil timeFormatter] stringFromDate:date];
    return dateTimeString;
}

+ (NSDateFormatter *)otherYearMessageFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setLocalizedDateFormatFromTemplate:@"MMM d, yyyy"];
    });
    return formatter;
}

+ (NSDateFormatter *)thisYearMessageFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setLocalizedDateFormatFromTemplate:@"MMM d"];
    });
    return formatter;
}

+ (NSDateFormatter *)thisWeekMessageFormatterShort
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setDateFormat:@"E"];
    });
    return formatter;
}

+ (NSDateFormatter *)thisWeekMessageFormatterLong
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setDateFormat:@"EEEE"];
    });
    return formatter;
}

@end

NS_ASSUME_NONNULL_END
