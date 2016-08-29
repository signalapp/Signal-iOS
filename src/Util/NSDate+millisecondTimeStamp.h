//  Created by Frederic Jacobs on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.


@interface NSDate (millisecondTimeStamp)

+ (uint64_t)ows_millisecondTimeStamp;
+ (NSDate *)ows_dateWithMillisecondsSince1970:(uint64_t)milliseconds;
+ (uint64_t)ows_millisecondsSince1970ForDate:(NSDate *)date;

@end
