//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSInteraction.h"

@class TSContactThread;

typedef enum {
    RPRecentCallTypeIncoming = 1,
    RPRecentCallTypeOutgoing,
    RPRecentCallTypeMissed,
} RPRecentCallType;

@interface TSCall : TSInteraction

@property (nonatomic, readonly) RPRecentCallType callType;

- (instancetype)initWithTimestamp:(uint64_t)timeStamp
                   withCallNumber:(NSString *)contactNumber
                         callType:(RPRecentCallType)callType
                         inThread:(TSContactThread *)thread;

@end
