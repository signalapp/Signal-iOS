#import <Foundation/Foundation.h>

@interface DateUtil : NSObject

+ (NSDateFormatter *)dateFormatter;
+ (NSDateFormatter *)weekdayFormatter;
+ (NSDateFormatter *)timeFormatter;
+ (BOOL)dateIsOlderThanOneDay:(NSDate *)date;
+ (BOOL)dateIsOlderThanOneWeek:(NSDate *)date;
+ (BOOL)dateIsToday:(NSDate *)date;

@end
