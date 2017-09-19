//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

NS_ASSUME_NONNULL_BEGIN

@interface NSDate (millisecondTimeStamp)

+ (uint64_t)ows_millisecondTimeStamp;
+ (NSDate *)ows_dateWithMillisecondsSince1970:(uint64_t)milliseconds;
+ (uint64_t)ows_millisecondsSince1970ForDate:(NSDate *)date;

@end

NS_ASSUME_NONNULL_END
