//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSCallHangupMessage.h"
#import <SignalServiceKit/SignalServiceKit-Swift.h>

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

- (nullable SSKProtoCallMessageHangup *)asProtobuf
{
    SSKProtoCallMessageHangupBuilder *builder = [SSKProtoCallMessageHangupBuilder new];

    builder.id = self.callId;
    
    NSError *error;
    SSKProtoCallMessageHangup *_Nullable result = [builder buildAndReturnError:&error];
    if (error || !result) {
        OWSFail(@"%@ could not build protobuf: %@", self.logTag, error);
        return nil;
    }
    return result;
}


@end

NS_ASSUME_NONNULL_END
