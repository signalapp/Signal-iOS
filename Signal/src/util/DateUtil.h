//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

@interface DateUtil : NSObject

+ (NSDateFormatter *)dateFormatter;
+ (NSDateFormatter *)weekdayFormatter;
+ (NSDateFormatter *)timeFormatter;
+ (BOOL)dateIsOlderThanOneDay:(NSDate *)date;
+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date;
+ (BOOL)dateIsToday:(NSDate *)date;

@end
