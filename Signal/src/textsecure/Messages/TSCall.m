//
//  TSCall.m
//  TextSecureKit
//
//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.
//

#import "TSCall.h"

@implementation TSCall

- (instancetype)initWithTimestamp:(uint64_t)timeStamp inThread:(TSThread*)thread
                        wasCaller:(BOOL)caller callType:(TSCallType)callType
                         duration:(NSNumber*)duration{
    self = [super initWithTimestamp:timeStamp inThread:thread];
    
    if (self) {
        _wasCaller = caller;
        _callType  = callType;
        _duration  = duration;
    }
    
    return self;
}

@end
