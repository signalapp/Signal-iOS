//
//  NSDate+millisecondTimeStamp.h
//  Signal
//
//  Created by Frederic Jacobs on 25/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDate (millisecondTimeStamp)
+ (uint64_t)ows_millisecondTimeStamp;
@end
