//
//  Copyright (c) 2021 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface DateUtil : NSObject

+ (NSDateFormatter *)dateFormatter;
+ (NSDateFormatter *)monthAndDayFormatter;
+ (NSDateFormatter *)shortDayOfWeekFormatter;

+ (BOOL)dateIsOlderThanToday:(NSDate *)date;
+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date;
+ (BOOL)dateIsToday:(NSDate *)date;
+ (BOOL)dateIsThisYear:(NSDate *)date;
+ (BOOL)dateIsYesterday:(NSDate *)date;

+ (NSString *)formatPastTimestampRelativeToNow:(uint64_t)pastTimestamp
    NS_SWIFT_NAME(formatPastTimestampRelativeToNow(_:));

+ (NSString *)formatTimestampShort:(uint64_t)timestamp;
+ (NSString *)formatDateShort:(NSDate *)date;

+ (NSString *)formatTimestampAsTime:(uint64_t)timestamp;
+ (NSString *)formatDateAsTime:(NSDate *)date;

+ (NSString *)formatTimestampAsDate:(uint64_t)timestamp;
+ (NSString *)formatDateAsDate:(NSDate *)date;

+ (BOOL)isTimestampFromLastHour:(uint64_t)timestamp;

+ (BOOL)dateIsOlderThanYesterday:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
