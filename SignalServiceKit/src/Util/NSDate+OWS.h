//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

// These NSTimeInterval constants provide simplified durations for readability.
#define kMinuteInterval 60
#define kHourInterval (60 * kMinuteInterval)
#define kDayInterval (24 * kHourInterval)
#define kWeekInterval (7 * kDayInterval)
#define kMonthInterval (30 * kDayInterval)

#define kSecondInMs 1000
#define kMinuteInMs (kSecondInMs * 60)
#define kHourInMs (kMinuteInMs * 60)
#define kDayInMs (kHourInMs * 24)
#define kWeekInMs (kDayInMs * 7)
#define kMonthInMs (kDayInMs * 30)

@interface NSDate (millisecondTimeStamp)

+ (uint64_t)ows_millisecondTimeStamp;
+ (NSDate *)ows_dateWithMillisecondsSince1970:(uint64_t)milliseconds;
+ (uint64_t)ows_millisecondsSince1970ForDate:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
