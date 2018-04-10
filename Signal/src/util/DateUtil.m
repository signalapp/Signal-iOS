//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "DateUtil.h"
#import <SignalMessaging/NSString+OWS.h>
#import <SignalServiceKit/NSDate+OWS.h>

NS_ASSUME_NONNULL_BEGIN

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

+ (NSDateFormatter *)monthAndDayFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        formatter.dateFormat = @"MMM d";
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

+ (BOOL)dateIsOlderThanOneDay:(NSDate *)date {
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];

    NSUInteger dateDayOfEra = [calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitEra forDate:date];
    NSUInteger nowDayOfEra = [calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitEra forDate:now];
    return dateDayOfEra < nowDayOfEra;
}

+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date {
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];

    NSUInteger dateDayOfEra = [calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitEra forDate:date];
    NSUInteger nowDayOfEra = [calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitEra forDate:now];
    return dateDayOfEra < (nowDayOfEra - 6);
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
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    return ([calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitEra forDate:date] ==
        [calendar ordinalityOfUnit:NSCalendarUnitDay inUnit:NSCalendarUnitEra forDate:now]);
}

+ (BOOL)dateIsThisYear:(NSDate *)date
{
    NSDate *now = [NSDate date];
    NSCalendar *calendar = [NSCalendar currentCalendar];
    return (
        [calendar component:NSCalendarUnitYear fromDate:date] == [calendar component:NSCalendarUnitYear fromDate:now]);
}

+ (BOOL)dateIsYesterday:(NSDate *)date
{
    NSDate *yesterday = [NSDate ows_dateWithMillisecondsSince1970:[NSDate ows_millisecondTimeStamp] - kDayInMs];
    return [self date:yesterday isEqualToDateIgnoringTime:date];
}

+ (NSString *)formatPastTimestampRelativeToNow:(uint64_t)pastTimestamp isRTL:(BOOL)isRTL
{
    OWSCAssert(pastTimestamp > 0);

    uint64_t nowTimestamp = [NSDate ows_millisecondTimeStamp];
    BOOL isFutureTimestamp = pastTimestamp >= nowTimestamp;

    NSDate *pastDate = [NSDate ows_dateWithMillisecondsSince1970:pastTimestamp];
    NSString *dateString;
    if (isFutureTimestamp || [self dateIsToday:pastDate]) {
        dateString = NSLocalizedString(@"DATE_TODAY", @"The current day.");
    } else if ([self dateIsYesterday:pastDate]) {
        dateString = NSLocalizedString(@"DATE_YESTERDAY", @"The day before today.");
    } else {
        dateString = [[self dateFormatter] stringFromDate:pastDate];
    }
    return [[dateString rtlSafeAppend:@" " isRTL:isRTL] rtlSafeAppend:[[self timeFormatter] stringFromDate:pastDate]
                                                                isRTL:isRTL];
}

@end

NS_ASSUME_NONNULL_END
