//  Created by Michael Kirk on 12/8/16.
//  Copyright © 2016 Open Whisper Systems. All rights reserved.

#import "OWSCallHangupMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCallHangupMessage

- (instancetype)initWithCallId:(UInt64)callId
{
    self = [super init];
    if (!self) {
        return self;
    }

    _callId = callId;

    return self;
}

- (OWSSignalServiceProtosCallMessageHangup *)asProtobuf
{
    OWSSignalServiceProtosCallMessageHangupBuilder *builder = [OWSSignalServiceProtosCallMessageHangupBuilder new];

    builder.id = self.callId;

    return [builder build];
}


@end

NS_ASSUME_NONNULL_END
