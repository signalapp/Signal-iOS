//
//  NSDate+millisecondTimeStamp.m
//  Signal
//
//  Created by Frederic Jacobs on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "NSDate+millisecondTimeStamp.h"
#import <chrono>

@implementation NSDate (millisecondTimeStamp)

+ (uint64_t)ows_millisecondTimeStamp{
    uint64_t milliseconds = std::chrono::system_clock::now().time_since_epoch()/std::chrono::milliseconds(1);
    return milliseconds;
}

@end
