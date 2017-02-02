//  Created by Frederic Jacobs on 12/11/14.
//  Copyright (c) 2014 Open Whisper Systems. All rights reserved.

#import "TSCall.h"
#import "TSContactThread.h"

NS_ASSUME_NONNULL_BEGIN

@implementation TSCall

- (instancetype)initWithTimestamp:(uint64_t)timestamp
                   withCallNumber:(NSString *)contactNumber
                         callType:(RPRecentCallType)callType
                         inThread:(TSContactThread *)thread
{
    self = [super initWithTimestamp:timestamp inThread:thread];

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

NS_ASSUME_NONNULL_END
