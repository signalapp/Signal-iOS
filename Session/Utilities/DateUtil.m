//
//  Copyright (c) 2019 Open Whisper Systems. All rights reserved.
//

#import "DateUtil.h"
#import <SignalCoreKit/NSDate+OWS.h>
#import <SignalUtilitiesKit/OWSFormat.h>
#import <SessionUtilitiesKit/NSString+SSK.h>

NS_ASSUME_NONNULL_BEGIN

static NSString *const DATE_FORMAT_WEEKDAY = @"EEEE";

@implementation DateUtil

+ (NSString *)getHourFormat {
    NSString *format = [NSDateFormatter dateFormatFromTemplate:@"j" options:0 locale:[NSLocale currentLocale]];
    NSRange range = [format rangeOfString:@"a"];
    BOOL is12HourTime = (range.location != NSNotFound);
    return (is12HourTime) ? @"h:mm a" : @"HH:mm";
}

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

+ (NSDateFormatter *)displayDateTodayFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale currentLocale];
        // 9:10 am
        formatter.dateFormat = [self getHourFormat];
    });

    return formatter;
}

+ (NSDateFormatter *)displayDateThisWeekDateFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale currentLocale];
        // Mon 11:36 pm
        formatter.dateFormat = [NSString stringWithFormat:@"EEE %@", [self getHourFormat]];
    });

    return formatter;
}

+ (NSDateFormatter *)displayDateThisYearDateFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale currentLocale];
        // Jun 6 10:12 am
        formatter.dateFormat = [NSString stringWithFormat:@"MMM d %@", [self getHourFormat]];
    });

    return formatter;
}

+ (NSDateFormatter *)displayDateOldDateFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        formatter.locale = [NSLocale currentLocale];
        formatter.dateStyle = NSDateFormatterMediumStyle;
        formatter.timeStyle = NSDateFormatterShortStyle;
        formatter.doesRelativeDateFormatting = YES;
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

+ (BOOL)isWithinOneMinute:(NSDate *)date
{
    NSTimeInterval interval = [[NSDate new] timeIntervalSince1970] - [date timeIntervalSince1970];
    return interval < 60;
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

+ (BOOL)dateIsThisWeek:(NSDate *)date
{
    return [self dateIsThisWeek:date now:[NSDate date]];
}

+ (BOOL)dateIsThisWeek:(NSDate *)date now:(NSDate *)now
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    return (
        [calendar component:NSCalendarUnitWeekOfYear fromDate:date] == [calendar component:NSCalendarUnitWeekOfYear fromDate:now]);
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

// Returns the difference in minutes, ignoring seconds.
// If both dates are the same date, returns 0.
// If firstDate is one minute before secondDate, returns 1.
//
// Note: Assumes both dates use the "current" calendar.
+ (NSInteger)MinutesFromFirstDate:(NSDate *)firstDate toSecondDate:(NSDate *)secondDate
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSCalendarUnit units = NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour | NSCalendarUnitMinute;
    NSDateComponents *comp1 = [calendar components:units fromDate:firstDate];
    NSDateComponents *comp2 = [calendar components:units fromDate:secondDate];
    NSDate *date1 = [calendar dateFromComponents:comp1];
    NSDate *date2 = [calendar dateFromComponents:comp2];
    return [[calendar components:NSCalendarUnitMinute fromDate:date1 toDate:date2 options:0] minute];
}

// Returns the difference in hours, ignoring minutes, seconds.
// If both dates are the same date, returns 0.
// If firstDate is an hour before secondDate, returns 1.
//
// Note: Assumes both dates use the "current" calendar.
+ (NSInteger)hoursFromFirstDate:(NSDate *)firstDate toSecondDate:(NSDate *)secondDate
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSCalendarUnit units = NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay | NSCalendarUnitHour;
    NSDateComponents *comp1 = [calendar components:units fromDate:firstDate];
    NSDateComponents *comp2 = [calendar components:units fromDate:secondDate];
    NSDate *date1 = [calendar dateFromComponents:comp1];
    NSDate *date2 = [calendar dateFromComponents:comp2];
    return [[calendar components:NSCalendarUnitHour fromDate:date1 toDate:date2 options:0] hour];
}

// Returns the difference in days, ignoring hours, minutes, seconds.
// If both dates are the same date, returns 0.
// If firstDate is a day before secondDate, returns 1.
//
// Note: Assumes both dates use the "current" calendar.
+ (NSInteger)daysFromFirstDate:(NSDate *)firstDate toSecondDate:(NSDate *)secondDate
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSCalendarUnit units = NSCalendarUnitEra | NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay;
    NSDateComponents *comp1 = [calendar components:units fromDate:firstDate];
    NSDateComponents *comp2 = [calendar components:units fromDate:secondDate];
    [comp1 setHour:12];
    [comp2 setHour:12];
    NSDate *date1 = [calendar dateFromComponents:comp1];
    NSDate *date2 = [calendar dateFromComponents:comp2];
    return [[calendar components:NSCalendarUnitDay fromDate:date1 toDate:date2 options:0] day];
}

// Returns the difference in years, ignoring shorter units of time.
// If both dates fall in the same year, returns 0.
// If firstDate is from the year before secondDate, returns 1.
//
// Note: Assumes both dates use the "current" calendar.
+ (NSInteger)yearsFromFirstDate:(NSDate *)firstDate toSecondDate:(NSDate *)secondDate
{
    NSCalendar *calendar = [NSCalendar currentCalendar];
    NSCalendarUnit units = NSCalendarUnitEra | NSCalendarUnitYear;
    NSDateComponents *comp1 = [calendar components:units fromDate:firstDate];
    NSDateComponents *comp2 = [calendar components:units fromDate:secondDate];
    [comp1 setHour:12];
    [comp2 setHour:12];
    NSDate *date1 = [calendar dateFromComponents:comp1];
    NSDate *date2 = [calendar dateFromComponents:comp2];
    return [[calendar components:NSCalendarUnitYear fromDate:date1 toDate:date2 options:0] year];
}

+ (NSString *)formatPastTimestampRelativeToNow:(uint64_t)pastTimestamp
{
    OWSCAssertDebug(pastTimestamp > 0);

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
    return [[dateString rtlSafeAppend:@" "] rtlSafeAppend:[[self timeFormatter] stringFromDate:pastDate]];
}

+ (NSString *)formatTimestampShort:(uint64_t)timestamp
{
    return [self formatDateShort:[NSDate ows_dateWithMillisecondsSince1970:timestamp]];
}

+ (NSString *)formatDateShort:(NSDate *)date
{
    OWSAssertIsOnMainThread();
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
        dateTimeString = [[DateUtil timeFormatter] stringFromDate:date];
    }

    return dateTimeString.localizedUppercaseString;
}

+ (NSString *)formatDateForDisplay:(NSDate *)date
{
    OWSAssertDebug(date);

    if (![self dateIsThisYear:date]) {
        // last year formatter: Nov 11 13:32 am, 2017
        return [self.displayDateOldDateFormatter stringFromDate:date];
    } else if (![self dateIsThisWeek:date]) {
        // this year formatter: Jun 6 10:12 am
        return [self.displayDateThisYearDateFormatter stringFromDate:date];
    } else if (![self dateIsToday:date]) {
        // day of week formatter: Thu 9:11 pm
        return [self.displayDateThisWeekDateFormatter stringFromDate:date];
    } else if (![self isWithinOneMinute:date]) {
        // today formatter: 8:32 am
        return [self.displayDateTodayFormatter stringFromDate:date];
    } else {
        return NSLocalizedString(@"DATE_NOW", @"");
    }
}

+ (NSString *)formatTimestampAsTime:(uint64_t)timestamp
{
    return [self formatDateAsTime:[NSDate ows_dateWithMillisecondsSince1970:timestamp]];
}

+ (NSString *)formatDateAsTime:(NSDate *)date
{
    OWSAssertDebug(date);

    NSString *dateTimeString = [[DateUtil timeFormatter] stringFromDate:date];
    return dateTimeString.localizedUppercaseString;
}

+ (NSDateFormatter *)otherYearMessageFormatter
{
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [NSDateFormatter new];
        [formatter setLocale:[NSLocale currentLocale]];
        [formatter setDateFormat:@"MMM d, yyyy"];
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
        [formatter setDateFormat:@"MMM d"];
    });
    return formatter;
}

+ (NSDateFormatter *)thisWeekMessageFormatter
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

+ (NSString *)formatMessageTimestamp:(uint64_t)timestamp
{
    NSDate *date = [NSDate ows_dateWithMillisecondsSince1970:timestamp];
    uint64_t nowTimestamp = [NSDate ows_millisecondTimeStamp];
    NSDate *nowDate = [NSDate ows_dateWithMillisecondsSince1970:nowTimestamp];

    NSCalendar *calendar = [NSCalendar currentCalendar];

    NSDateComponents *relativeDiffComponents =
        [calendar components:NSCalendarUnitMinute | NSCalendarUnitHour fromDate:date toDate:nowDate options:0];

    NSInteger minutesDiff = MAX(0, [relativeDiffComponents minute]);
    NSInteger hoursDiff = MAX(0, [relativeDiffComponents hour]);
    if (hoursDiff < 1 && minutesDiff < 1) {
        return NSLocalizedString(@"DATE_NOW", @"The present; the current time.");
    }

    if (hoursDiff < 1) {
        NSString *minutesString = [OWSFormat formatInt:(int)minutesDiff];
        return [NSString stringWithFormat:NSLocalizedString(@"DATE_MINUTES_AGO_FORMAT",
                                              @"Format string for a relative time, expressed as a certain number of "
                                              @"minutes in the past. Embeds {{The number of minutes}}."),
                         minutesString];
    }

    // Note: we are careful to treat "future" dates as "now".
    NSInteger yearsDiff = [self yearsFromFirstDate:date toSecondDate:nowDate];
    if (yearsDiff > 0) {
        // "Long date" + locale-specific "short" time format.
        NSString *dayOfWeek = [self.otherYearMessageFormatter stringFromDate:date];
        NSString *formattedTime = [[self timeFormatter] stringFromDate:date];
        return [[dayOfWeek rtlSafeAppend:@" "] rtlSafeAppend:formattedTime];
    }

    NSInteger daysDiff = [self daysFromFirstDate:date toSecondDate:nowDate];
    if (daysDiff >= 7) {
        // "Short date" + locale-specific "short" time format.
        NSString *dayOfWeek = [self.thisYearMessageFormatter stringFromDate:date];
        NSString *formattedTime = [[self timeFormatter] stringFromDate:date];
        return [[dayOfWeek rtlSafeAppend:@" "] rtlSafeAppend:formattedTime];
    } else if (daysDiff > 0) {
        // "Day of week" + locale-specific "short" time format.
        NSString *dayOfWeek = [self.thisWeekMessageFormatter stringFromDate:date];
        NSString *formattedTime = [[self timeFormatter] stringFromDate:date];
        return [[dayOfWeek rtlSafeAppend:@" "] rtlSafeAppend:formattedTime];
    } else {
        NSString *hoursString = [OWSFormat formatInt:(int)hoursDiff];
        return [NSString stringWithFormat:NSLocalizedString(@"DATE_HOURS_AGO_FORMAT",
                                              @"Format string for a relative time, expressed as a certain number of "
                                              @"hours in the past. Embeds {{The number of hours}}."),
                         hoursString];
    }
}

+ (BOOL)isTimestampFromLastHour:(uint64_t)timestamp
{
    NSDate *date = [NSDate ows_dateWithMillisecondsSince1970:timestamp];
    uint64_t nowTimestamp = [NSDate ows_millisecondTimeStamp];
    NSDate *nowDate = [NSDate ows_dateWithMillisecondsSince1970:nowTimestamp];

    NSCalendar *calendar = [NSCalendar currentCalendar];

    NSInteger hoursDiff
        = MAX(0, [[calendar components:NSCalendarUnitHour fromDate:date toDate:nowDate options:0] hour]);
    return hoursDiff < 1;
}

+ (NSString *)exemplaryNowTimeFormat
{
    return NSLocalizedString(@"DATE_NOW", @"The present; the current time.").localizedUppercaseString;
}

+ (NSString *)exemplaryMinutesTimeFormat
{
    NSString *minutesString = [OWSFormat formatInt:(int)59];
    return [NSString stringWithFormat:NSLocalizedString(@"DATE_MINUTES_AGO_FORMAT",
                                          @"Format string for a relative time, expressed as a certain number of "
                                          @"minutes in the past. Embeds {{The number of minutes}}."),
                     minutesString]
        .uppercaseString;
}

+ (BOOL)isSameDayWithTimestamp:(uint64_t)timestamp1 timestamp:(uint64_t)timestamp2
{
    return [self isSameDayWithDate:[NSDate ows_dateWithMillisecondsSince1970:timestamp1]
                              date:[NSDate ows_dateWithMillisecondsSince1970:timestamp2]];
}

+ (BOOL)isSameDayWithDate:(NSDate *)date1 date:(NSDate *)date2
{
    NSInteger dayDifference = [self daysFromFirstDate:date1 toSecondDate:date2];
    return dayDifference == 0;
}

+ (BOOL)isSameHourWithTimestamp:(uint64_t)timestamp1 timestamp:(uint64_t)timestamp2
{
    return [self isSameHourWithDate:[NSDate ows_dateWithMillisecondsSince1970:timestamp1]
                               date:[NSDate ows_dateWithMillisecondsSince1970:timestamp2]];
}

+ (BOOL)isSameHourWithDate:(NSDate *)date1 date:(NSDate *)date2
{
    NSInteger hourDifference = [self hoursFromFirstDate:date1 toSecondDate:date2];
    return hourDifference == 0;
}

+ (BOOL)shouldShowDateBreakForTimestamp:(uint64_t)timestamp1 timestamp:(uint64_t)timestamp2
{
    NSInteger maxMinutesBetweenTwoDateBreaks = 5;
    NSDate *date1 = [NSDate ows_dateWithMillisecondsSince1970:timestamp1];
    NSDate *date2 = [NSDate ows_dateWithMillisecondsSince1970:timestamp2];
    return [self MinutesFromFirstDate:date1 toSecondDate:date2] > maxMinutesBetweenTwoDateBreaks;
}

@end

NS_ASSUME_NONNULL_END
