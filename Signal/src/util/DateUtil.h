//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface DateUtil : NSObject

+ (NSDateFormatter *)dateFormatter;
+ (NSDateFormatter *)timeFormatter;
+ (NSDateFormatter *)monthAndDayFormatter;
+ (NSDateFormatter *)shortDayOfWeekFormatter;

+ (BOOL)dateIsOlderThanToday:(NSDate *)date;
+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date;
+ (BOOL)dateIsToday:(NSDate *)date;
+ (BOOL)dateIsThisYear:(NSDate *)date;
+ (BOOL)dateIsYesterday:(NSDate *)date;

+ (NSString *)formatPastTimestampRelativeToNow:(uint64_t)pastTimestamp
                                         isRTL:(BOOL)isRTL NS_SWIFT_NAME(formatPastTimestampRelativeToNow(_:isRTL:));

@end

NS_ASSUME_NONNULL_END
