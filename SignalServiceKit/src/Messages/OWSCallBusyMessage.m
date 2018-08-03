//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCallBusyMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

- (nullable SSKProtoCallMessageBusy *)asProtobuf
{
    SSKProtoCallMessageBusyBuilder *builder = [SSKProtoCallMessageBusyBuilder new];

    builder.id = self.callId;
    
    NSError *error;
    SSKProtoCallMessageBusy *_Nullable result = [builder buildAndReturnError:&error];
    if (error || !result) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return result;
}

@end

NS_ASSUME_NONNULL_END
