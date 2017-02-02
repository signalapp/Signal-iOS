//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSCallBusyMessage.h"
#import "OWSSignalServiceProtos.pb.h"

NS_ASSUME_NONNULL_BEGIN

@implementation OWSCallBusyMessage

- (instancetype)initWithCallId:(UInt64)callId
{
    self = [super init];
    if (!self) {
        return self;
    }

    _callId = callId;

    return self;
}

- (OWSSignalServiceProtosCallMessageBusy *)asProtobuf
{
    OWSSignalServiceProtosCallMessageBusyBuilder *builder = [OWSSignalServiceProtosCallMessageBusyBuilder new];

    builder.id = self.callId;

    return [builder build];
}

@end

NS_ASSUME_NONNULL_END
