//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSCall.h"
#import "TSContactThread.h"

@implementation TSCall

- (instancetype)initWithTimestamp:(uint64_t)timeStamp
                   withCallNumber:(NSString *)contactNumber
                         callType:(RPRecentCallType)callType
                         inThread:(TSContactThread *)thread {
    self = [super initWithTimestamp:timeStamp inThread:thread];

    if (self) {
        _callType = callType;
    }

    return self;
}

- (NSString *)description {
    switch (_callType) {
        case RPRecentCallTypeIncoming:
            return NSLocalizedString(@"INCOMING_CALL", @"");
        case RPRecentCallTypeOutgoing:
            return NSLocalizedString(@"OUTGOING_CALL", @"");
        case RPRecentCallTypeMissed:
            return NSLocalizedString(@"MISSED_CALL", @"");
    }
}

@end
