//
// Copyright 2014 Signal Messenger, LLC
// SPDX-License-Identifier: AGPL-3.0-only
//

NS_ASSUME_NONNULL_BEGIN

@interface DateUtil : NSObject

+ (NSDateFormatter *)dateFormatter;
+ (NSDateFormatter *)monthAndDayFormatter;
+ (NSDateFormatter *)shortDayOfWeekFormatter;
+ (NSDateFormatter *)weekdayFormatter;

+ (BOOL)dateIsOlderThanToday:(NSDate *)date;
+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date;
+ (BOOL)dateIsToday:(NSDate *)date;
+ (BOOL)dateIsThisYear:(NSDate *)date;
+ (BOOL)dateIsYesterday:(NSDate *)date;

+ (NSString *)formatPastTimestampRelativeToNow:(uint64_t)pastTimestamp
    NS_SWIFT_NAME(formatPastTimestampRelativeToNow(_:));

+ (NSString *)formatTimestampShort:(uint64_t)timestamp;
+ (NSString *)formatDateShort:(NSDate *)date;

+ (NSString *)formatTimestampAsTime:(uint64_t)timestamp NS_SWIFT_NAME(formatTimestampAsTime(_:));
+ (NSString *)formatDateAsTime:(NSDate *)date NS_SWIFT_NAME(formatDateAsTime(_:));

+ (NSString *)formatTimestampAsDate:(uint64_t)timestamp NS_SWIFT_NAME(formatTimestampAsDate(_:));
+ (NSString *)formatDateAsDate:(NSDate *)date NS_SWIFT_NAME(formatDateAsDate(_:));

+ (BOOL)isTimestampFromLastHour:(uint64_t)timestamp NS_SWIFT_NAME(isTimestampFromLastHour(_:));

+ (BOOL)dateIsOlderThanYesterday:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
